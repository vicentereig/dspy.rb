#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'optparse'
require 'json'
require 'csv'
require 'fileutils'
require 'securerandom'
require 'time'
require 'gepa/logging'

require 'dspy'
require 'sorbet-runtime'

EXAMPLE_ROOT = File.expand_path(__dir__)
DATA_DIR = File.join(EXAMPLE_ROOT, 'data')
RESULTS_DIR = File.join(EXAMPLE_ROOT, 'results')
DATASET_CACHE_DIR = File.join(DATA_DIR, 'ade_parquet')
DSPY_DATASET_ID = 'ade-benchmark-corpus/ade_corpus_v2'

FileUtils.mkdir_p(DATA_DIR)
FileUtils.mkdir_p(RESULTS_DIR)
FileUtils.mkdir_p(DATASET_CACHE_DIR)

module ADEExampleGEPA
  class ADETextClassifier < DSPy::Signature
    description 'Determine if a clinical sentence describes an adverse drug event (ADE)'

    class ADELabel < T::Enum
      enums do
        NotRelated = new('0')
        Related = new('1')
      end
    end

    input do
      const :text, String, description: 'Clinical sentence or patient report'
    end

    output do
      const :label, ADELabel, description: 'Whether the text is ADE-related'
    end
  end

  ExampleEvaluation = Struct.new(:accuracy, :precision, :recall, :f1)

  module_function

  def build_examples(rows)
    rows.map do |row|
      label = ADETextClassifier::ADELabel.deserialize(row.fetch('label', 0).to_s)
      DSPy::Example.new(
        signature_class: ADETextClassifier,
        input: { text: row.fetch('text', '') },
        expected: { label: label }
      )
    end
  end

  def split_examples(examples, train_ratio:, val_ratio:, seed: 42)
    shuffled = examples.shuffle(random: Random.new(seed))
    train_size = (shuffled.size * train_ratio).round
    val_size = (shuffled.size * val_ratio).round

    train = shuffled.first(train_size)
    val = shuffled.slice(train_size, val_size) || []
    test = shuffled.drop(train_size + val_size)
    [train, val, test]
  end

  def label_from_prediction(prediction)
    value =
      if prediction.respond_to?(:label)
        prediction.label
      elsif prediction.is_a?(Hash)
        prediction[:label] || prediction['label']
      else
        prediction
      end

    return value if value.is_a?(ADETextClassifier::ADELabel)

    ADETextClassifier::ADELabel.deserialize(value.to_s)
  rescue StandardError
    ADETextClassifier::ADELabel::NotRelated
  end

  def evaluate(program, examples)
    return ExampleEvaluation.new(0.0, 0.0, 0.0, 0.0) if examples.empty?

    totals = {
      correct: 0,
      tp: 0,
      fp: 0,
      fn: 0
    }

    examples.each do |example|
      expected = example.expected_values[:label]
      prediction = program.call(**example.input_values)
      predicted = label_from_prediction(prediction)

      totals[:correct] += 1 if predicted == expected

      if expected == ADETextClassifier::ADELabel::Related
        totals[:tp] += 1 if predicted == ADETextClassifier::ADELabel::Related
        totals[:fn] += 1 if predicted == ADETextClassifier::ADELabel::NotRelated
      elsif predicted == ADETextClassifier::ADELabel::Related
        totals[:fp] += 1
      end
    end

    accuracy = totals[:correct].to_f / examples.size
    precision = safe_divide(totals[:tp], totals[:tp] + totals[:fp])
    recall = safe_divide(totals[:tp], totals[:tp] + totals[:fn])
    f1 = safe_divide(2 * precision * recall, precision + recall)

    ExampleEvaluation.new(accuracy, precision, recall, f1)
  end

  def safe_divide(numerator, denominator)
    return 0.0 if denominator.nil? || denominator.zero?

    numerator.to_f / denominator
  end

  def snippet(text, length: 120)
    sanitized = text.to_s.strip.gsub(/\s+/, ' ')
    return sanitized if sanitized.length <= length

    "#{sanitized[0, length]}..."
  end
end

options = {
  limit: 30,
  max_metric_calls: 600,
  minibatch_size: 6,
  seed: 42,
  track_stats_path: nil
}

OptionParser.new do |parser|
  parser.banner = 'Usage: bundle exec ruby examples/ade_optimizer_gepa/main.rb [options]'

  parser.on('-l', '--limit N', Integer, 'Number of ADE examples to download (default: 30)') do |limit|
    options[:limit] = limit
  end

  parser.on('--max-metric-calls N', Integer, 'GEPA max metric calls (default: 600)') do |calls|
    options[:max_metric_calls] = calls
  end

  parser.on('--minibatch-size N', Integer, 'GEPA minibatch size (default: 6)') do |batch|
    options[:minibatch_size] = batch
  end

  parser.on('--seed N', Integer, 'Random seed for dataset splits (default: 42)') do |seed|
    options[:seed] = seed
  end

  parser.on('--track-stats [PATH]', 'Persist GEPA events to PATH (default: results/gepa_events.jsonl)') do |path|
    options[:track_stats_path] = path || File.join(RESULTS_DIR, 'gepa_events.jsonl')
  end

  parser.on('-h', '--help', 'Show this help message') do
    puts parser
    exit
  end
end.parse!

unless ENV['OPENAI_API_KEY']
  warn '⚠️  Please set OPENAI_API_KEY in your environment before running this example.'
  exit 1
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  config.logger = Dry.Logger(:dspy, formatter: :string) do |logger|
    logger.add_backend(stream: File.join(EXAMPLE_ROOT, '../../log/dspy_ade_gepa.log'))
  end
end

puts '🏥 ADE GEPA Optimization Demo'
puts '============================='
puts "Limit           : #{options[:limit]}"
puts "Max metric calls: #{options[:max_metric_calls]}"
puts "Minibatch size  : #{options[:minibatch_size]}"
puts "Random Seed     : #{options[:seed]}"

dataset = DSPy::Datasets.fetch(DSPY_DATASET_ID, split: 'train', cache_dir: DATASET_CACHE_DIR)
rows = dataset.rows(limit: options[:limit])

if rows.empty?
  warn '❌ Failed to download ADE dataset rows. Please check your network connection.'
  exit 1
end

puts "\n📦 Downloaded #{rows.size} ADE rows from Hugging Face parquet (split: #{dataset.split})"

examples = ADEExampleGEPA.build_examples(rows)
puts "🧪 Prepared #{examples.size} DSPy examples"

train_examples, val_examples, test_examples = ADEExampleGEPA.split_examples(examples, train_ratio: 0.6, val_ratio: 0.2, seed: options[:seed])

puts '📊 Dataset split:'
puts "   • Train: #{train_examples.size}"
puts "   • Val  : #{val_examples.size}"
puts "   • Test : #{test_examples.size}"

experiment_tracker = nil
if options[:track_stats_path]
  FileUtils.mkdir_p(File.dirname(options[:track_stats_path]))
  File.write(options[:track_stats_path], '')

  experiment_tracker = GEPA::Logging::ExperimentTracker.new
  experiment_tracker.with_subscriber do |event|
    File.open(options[:track_stats_path], 'a') do |io|
      io.puts(JSON.generate(event))
    end
  end

  puts "🛰  Tracking GEPA events at #{options[:track_stats_path]}"
end

min_required_calls = val_examples.size + (options[:minibatch_size] * 2)
if options[:max_metric_calls] < min_required_calls
  suggested_calls = [min_required_calls, val_examples.size * 2].max
  warn "⚠️  Increasing max metric calls from #{options[:max_metric_calls]} to #{suggested_calls} to cover validation evaluation."
  options[:max_metric_calls] = suggested_calls
end

baseline_program = DSPy::Predict.new(ADEExampleGEPA::ADETextClassifier)
baseline_instruction = baseline_program.prompt.instruction rescue nil
snippet_for = lambda do |text|
  text.to_s.lines.map(&:strip).find { |line| !line.empty? }
end
baseline_metrics = ADEExampleGEPA.evaluate(baseline_program, test_examples)

puts "\n📈 Baseline performance (unoptimized prompt):"
puts "   • Accuracy : #{(baseline_metrics.accuracy * 100).round(2)}%"
puts "   • Precision: #{(baseline_metrics.precision * 100).round(2)}%"
puts "   • Recall   : #{(baseline_metrics.recall * 100).round(2)}%"
puts "   • F1 Score : #{(baseline_metrics.f1 * 100).round(2)}%"
if (line = snippet_for.call(baseline_instruction))
  puts "\n📝 Baseline instruction snippet:"
  puts line
end

# Metric returns DSPy::Prediction so GEPA sees both score and textual feedback.
metric = lambda do |example, prediction|
  expected = example.expected_values[:label]
  predicted = ADEExampleGEPA.label_from_prediction(prediction)
  score = predicted == expected ? 1.0 : 0.0
  snippet = ADEExampleGEPA.snippet(example.input_values[:text])
  feedback = if predicted == expected
    "Correct (#{expected.serialize}) for: \"#{snippet}\""
  else
    "Misclassified (expected #{expected.serialize}, predicted #{predicted.serialize}) for: \"#{snippet}\""
  end
  DSPy::Prediction.new(score: score, feedback: feedback)
end
# Optional predictor-level feedback. Leave empty to rely solely on the metric above.
feedback_map = {
  'self' => lambda do |predictor_output:, predictor_inputs:, module_inputs:, module_outputs:, captured_trace:|
    expected = module_inputs.expected_values[:label]
    predicted = ADEExampleGEPA.label_from_prediction(predictor_output)
    score = predicted == expected ? 1.0 : 0.0
    snippet = ADEExampleGEPA.snippet(predictor_inputs[:text], length: 80)
    DSPy::Prediction.new(
      score: score,
      feedback: "Classifier saw \"#{snippet}\" → #{predicted.serialize} (expected #{expected.serialize})"
    )
  end
}

reflection_lm = DSPy::ReflectionLM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

teleprompter = DSPy::Teleprompt::GEPA.new(
  metric: metric,
  reflection_lm: reflection_lm,
  feedback_map: feedback_map,
  experiment_tracker: experiment_tracker,
  config: {
    max_metric_calls: options[:max_metric_calls],
    minibatch_size: options[:minibatch_size],
    skip_perfect_score: false
  }
)

puts "\n🚀 Running GEPA optimization (max metric calls: #{options[:max_metric_calls]})..."
result = teleprompter.compile(baseline_program, trainset: train_examples, valset: val_examples)

optimized_program = result.optimized_program
optimized_metrics = ADEExampleGEPA.evaluate(optimized_program, test_examples)

puts "\n🏁 Optimized program performance:"
puts "   • Accuracy : #{(optimized_metrics.accuracy * 100).round(2)}%"
puts "   • Precision: #{(optimized_metrics.precision * 100).round(2)}%"
puts "   • Recall   : #{(optimized_metrics.recall * 100).round(2)}%"
puts "   • F1 Score : #{(optimized_metrics.f1 * 100).round(2)}%"

accuracy_improvement = (optimized_metrics.accuracy - baseline_metrics.accuracy) * 100
puts "\n📣 Accuracy improvement: #{accuracy_improvement.round(2)} percentage points"
puts "   • Candidates explored: #{result.metadata[:candidates]}"
puts "   • Best score (val): #{result.best_score_value.round(4)}"

summary = {
  timestamp: Time.now.utc.iso8601,
  limit: options[:limit],
  max_metric_calls: options[:max_metric_calls],
  minibatch_size: options[:minibatch_size],
  baseline: {
    accuracy: baseline_metrics.accuracy,
    precision: baseline_metrics.precision,
    recall: baseline_metrics.recall,
    f1: baseline_metrics.f1
  },
  optimized: {
    accuracy: optimized_metrics.accuracy,
    precision: optimized_metrics.precision,
    recall: optimized_metrics.recall,
    f1: optimized_metrics.f1
  },
  candidates: result.metadata[:candidates],
  best_score: result.best_score_value
}

summary_path = File.join(RESULTS_DIR, 'gepa_summary.json')
File.write(summary_path, JSON.pretty_generate(summary))

csv_path = File.join(RESULTS_DIR, 'gepa_metrics.csv')
CSV.open(csv_path, 'w') do |csv|
  csv << %w[metric baseline optimized]
  csv << ['accuracy', baseline_metrics.accuracy, optimized_metrics.accuracy]
  csv << ['precision', baseline_metrics.precision, optimized_metrics.precision]
  csv << ['recall', baseline_metrics.recall, optimized_metrics.recall]
  csv << ['f1', baseline_metrics.f1, optimized_metrics.f1]
end

puts "\n📂 Results saved to:"
puts "   • #{summary_path}"
puts "   • #{csv_path}"
puts "   • #{options[:track_stats_path]}" if options[:track_stats_path]

puts "\n✨ Sample optimized instruction snippet:"
instruction = optimized_program.prompt.instruction rescue nil
if (line = snippet_for.call(instruction))
  puts line
else
  puts '(no instruction recorded)'
end

puts "\nDone!"
