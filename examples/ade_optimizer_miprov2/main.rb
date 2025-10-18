#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'optparse'
require 'json'
require 'csv'
require 'fileutils'
require 'securerandom'

require 'dspy'
require 'sorbet-runtime'

EXAMPLE_ROOT = File.expand_path(__dir__)
DATA_DIR = File.join(EXAMPLE_ROOT, 'data')
RESULTS_DIR = File.join(EXAMPLE_ROOT, 'results')

FileUtils.mkdir_p(DATA_DIR)
FileUtils.mkdir_p(RESULTS_DIR)

module ADEExample
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
end

options = {
  limit: 300,
  trials: 6,
  seed: 42
}

OptionParser.new do |parser|
parser.banner = 'Usage: bundle exec ruby examples/ade_optimizer_miprov2/main.rb [options]'

  parser.on('-l', '--limit N', Integer, 'Number of ADE examples to download (default: 300)') do |limit|
    options[:limit] = limit
  end

  parser.on('-t', '--trials N', Integer, 'Number of MIPROv2 trials (default: 6)') do |trials|
    options[:trials] = trials
  end

  parser.on('--seed N', Integer, 'Random seed for dataset splits (default: 42)') do |seed|
    options[:seed] = seed
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
    logger.add_backend(stream: File.join(EXAMPLE_ROOT, '../../log/dspy_ade_example.log'))
  end
end

puts '🏥 ADE MIPROv2 Optimization Demo'
puts '================================'
puts "Limit       : #{options[:limit]}"
puts "Trials      : #{options[:trials]}"
puts "Random Seed : #{options[:seed]}"

rows = DSPy::Datasets::ADE.examples(limit: options[:limit], offset: 0, split: 'train', cache_dir: DATA_DIR)

if rows.empty?
  warn "❌ Failed to download ADE dataset rows. Please check your network connection."
  exit 1
end

puts "\n📦 Downloaded #{rows.size} ADE rows from Hugging Face"

examples = ADEExample.build_examples(rows)
puts "🧪 Prepared #{examples.size} DSPy examples"

train_examples, val_examples, test_examples = ADEExample.split_examples(examples, train_ratio: 0.6, val_ratio: 0.2, seed: options[:seed])

puts '📊 Dataset split:'
puts "   • Train: #{train_examples.size}"
puts "   • Val  : #{val_examples.size}"
puts "   • Test : #{test_examples.size}"

baseline_program = DSPy::Predict.new(ADEExample::ADETextClassifier)
baseline_metrics = ADEExample.evaluate(baseline_program, test_examples)

puts "\n📈 Baseline performance (unoptimized prompt):"
puts "   • Accuracy : #{(baseline_metrics.accuracy * 100).round(2)}%"
puts "   • Precision: #{(baseline_metrics.precision * 100).round(2)}%"
puts "   • Recall   : #{(baseline_metrics.recall * 100).round(2)}%"
puts "   • F1 Score : #{(baseline_metrics.f1 * 100).round(2)}%"

metric = proc do |example, prediction|
  expected = example.expected_values[:label]
  predicted = ADEExample.label_from_prediction(prediction)
  predicted == expected
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
optimizer.configure do |config|
  config.num_trials = options[:trials]
  config.num_instruction_candidates = 3
  config.bootstrap_sets = 2
  config.max_bootstrapped_examples = 2
  config.max_labeled_examples = 4
  config.optimization_strategy = :adaptive
end

puts "\n🚀 Running MIPROv2 optimization (#{options[:trials]} trials)..."
result = optimizer.compile(baseline_program, trainset: train_examples, valset: val_examples)

trial_logs = result.optimization_trace[:trial_logs] || {}
if trial_logs.any?
  puts "\n📝 Trial-by-trial instruction snapshots:"
  trial_logs.sort.each do |trial_number, entry|
    instructions = entry.dig(:instructions)
    next unless instructions

    puts "\n  Trial ##{trial_number}:"
    instructions.each do |predictor_index, instruction|
      puts "    • Predictor #{predictor_index}: #{instruction || '(no instruction)'}"
    end
  end
end

optimized_program = result.optimized_program
optimized_metrics = ADEExample.evaluate(optimized_program, test_examples)

puts "\n🏁 Optimized program performance:"
puts "   • Accuracy : #{(optimized_metrics.accuracy * 100).round(2)}%"
puts "   • Precision: #{(optimized_metrics.precision * 100).round(2)}%"
puts "   • Recall   : #{(optimized_metrics.recall * 100).round(2)}%"
puts "   • F1 Score : #{(optimized_metrics.f1 * 100).round(2)}%"

improvement = (optimized_metrics.accuracy - baseline_metrics.accuracy) * 100
puts "\n📣 Accuracy improvement: #{improvement.round(2)} percentage points"

summary = {
  timestamp: Time.now.utc.iso8601,
  limit: options[:limit],
  trials: options[:trials],
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
  best_score: result.best_score_value,
  best_instruction: nil,
  total_trials: result.history[:total_trials],
  optimization_strategy: result.history[:optimization_strategy]
}

best_instruction_text = result.metadata[:best_instruction].to_s

if best_instruction_text.empty?
  best_trial = trial_logs.values.compact.max_by { |entry| entry[:score] || 0 }
  if best_trial && best_trial[:instructions]&.any?
    best_instruction_text = best_trial[:instructions].values.compact.first.to_s
  end
end

summary[:best_instruction] = best_instruction_text

summary_path = File.join(RESULTS_DIR, 'summary.json')
File.write(summary_path, JSON.pretty_generate(summary))

csv_path = File.join(RESULTS_DIR, 'metrics.csv')
CSV.open(csv_path, 'w') do |csv|
  csv << %w[metric baseline optimized]
  csv << ['accuracy', baseline_metrics.accuracy, optimized_metrics.accuracy]
  csv << ['precision', baseline_metrics.precision, optimized_metrics.precision]
  csv << ['recall', baseline_metrics.recall, optimized_metrics.recall]
  csv << ['f1', baseline_metrics.f1, optimized_metrics.f1]
end

trial_log_path = File.join(RESULTS_DIR, 'trial_logs.json')
File.write(trial_log_path, JSON.pretty_generate(result.optimization_trace[:trial_logs]))

puts "\n📂 Results saved to:"
puts "   • #{summary_path}"
puts "   • #{csv_path}"
puts "   • #{trial_log_path}"

puts "\n✨ Best instruction snippet:"
puts best_instruction_text.empty? ? '(no instruction recorded)' : best_instruction_text.lines.first.to_s.strip

puts "\nDone!"
