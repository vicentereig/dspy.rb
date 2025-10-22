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
require_relative 'ade_example'

EXAMPLE_ROOT = File.expand_path(__dir__)
DATA_DIR = File.join(EXAMPLE_ROOT, 'data')
RESULTS_DIR = File.join(EXAMPLE_ROOT, 'results')
DATASET_CACHE_DIR = File.join(DATA_DIR, 'ade_parquet')
DSPY_DATASET_ID = 'ade-benchmark-corpus/ade_corpus_v2'
AUTO_PRESET_CHOICES = %w[light medium heavy none].freeze

FileUtils.mkdir_p(DATA_DIR)
FileUtils.mkdir_p(RESULTS_DIR)
FileUtils.mkdir_p(DATASET_CACHE_DIR)

def serialize_few_shot_payload(value)
  case value
  when DSPy::FewShotExample
    value.to_h
  when Hash
    value.transform_values { |inner| serialize_few_shot_payload(inner) }
  when Array
    value.map { |element| serialize_few_shot_payload(element) }
  else
    value
  end
end

def serialize_trial_logs(trial_logs)
  trial_logs.transform_values { |entry| serialize_few_shot_payload(entry) }
end

def resolve_api_key_for(model_id)
  provider = model_id.to_s.split('/', 2).first
  env_var = case provider
            when 'openai'
              'OPENAI_API_KEY'
            when 'anthropic'
              'ANTHROPIC_API_KEY'
            when 'gemini'
              'GEMINI_API_KEY'
            else
              provider&.upcase&.gsub(/[^A-Z0-9]/, '_')&.then { |value| "#{value}_API_KEY" }
            end

  [provider, env_var, env_var ? ENV[env_var] : nil]
end

options = {
  limit: 300,
  trials: 6,
  seed: nil,
  auto: nil,
  model: 'openai/gpt-5-2025-08-07'
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: bundle exec ruby examples/ade_optimizer_miprov2/main.rb [options]'

  opts.on('-l', '--limit N', Integer, 'Number of ADE examples to download (default: 300)') do |limit|
    options[:limit] = limit
  end

  opts.on('-t', '--trials N', Integer, 'Number of MIPROv2 trials (default: 6)') do |trials|
    options[:trials] = trials
  end

  opts.on('--auto MODE', String, "Auto preset (#{AUTO_PRESET_CHOICES.join(', ')})") do |mode|
    normalized = mode.strip.downcase
    unless AUTO_PRESET_CHOICES.include?(normalized)
      raise OptionParser::InvalidArgument, "invalid auto preset '#{mode}'. Must be one of #{AUTO_PRESET_CHOICES.join(', ')}"
    end
    options[:auto] = normalized
  end

  opts.on('--model ID', String,
          'Fully-qualified model ID (default: openai/gpt-5-2025-08-07). Examples: openai/gpt-5-2025-08-07, openai/gpt-5-mini-2025-08-07, openai/gpt-5-nano-2025-08-07, anthropic/claude-sonnet-4-5-20250929, gemini/gemini-2.5-pro') do |model_id|
    options[:model] = model_id.strip
  end

  opts.on('--seed N', Integer, 'Random seed for dataset splits (default: 42)') do |seed|
    options[:seed] = seed
  end

  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "❌ #{e.message}"
  warn parser
  exit 1
end

options[:auto] = nil if options[:auto] == 'none'

unless options[:model].include?('/')
  warn "⚠️  Invalid model '#{options[:model]}'. Please use the format provider/model (e.g., openai/gpt-4o-mini)."
  exit 1
end

provider, env_var, api_key = resolve_api_key_for(options[:model])

if api_key.to_s.strip.empty?
  warn "⚠️  Please set #{env_var || 'the appropriate *_API_KEY variable'} in your environment before running this example (model: #{options[:model]})."
  exit 1
end

sanitized_provider = (provider || 'unknown').gsub(/[^A-Za-z0-9._-]/, '_')
raw_model_identifier = options[:model].split('/', 2).last || options[:model]
sanitized_model_identifier = raw_model_identifier.gsub(/[^A-Za-z0-9._-]/, '_')
model_results_dir = File.join(RESULTS_DIR, sanitized_provider, sanitized_model_identifier)
FileUtils.mkdir_p(model_results_dir)

DSPy.configure do |config|
  config.lm = DSPy::LM.new(options[:model], api_key: api_key)
  config.logger = Dry.Logger(:dspy, formatter: :string) do |logger|
    logger.add_backend(stream: File.join(EXAMPLE_ROOT, '../../log/dspy_ade_example.log'))
  end
end

puts '🏥 ADE MIPROv2 Optimization Demo'
puts '================================'
puts "Limit       : #{options[:limit]}"
if options[:auto]
  puts "Auto Preset : #{options[:auto].capitalize}"
else
  puts "Trials      : #{options[:trials]}"
end
puts "Model       : #{options[:model]}"
effective_seed = options[:seed] || Random.new_seed
puts "Random Seed : #{effective_seed}"

dataset = DSPy::Datasets.fetch(DSPY_DATASET_ID, split: 'train', cache_dir: DATASET_CACHE_DIR)
all_rows = dataset.rows  # Load all rows (23,516 total)

if all_rows.empty?
  warn "❌ Failed to download ADE dataset rows. Please check your network connection."
  exit 1
end

# Shuffle before limiting to ensure class balance
# (Dataset is sorted: first ~6.8k are positive, last ~16.7k are negative)
shuffled_rows = all_rows.shuffle(random: Random.new(effective_seed))
rows = shuffled_rows.first(options[:limit])

puts "\n📦 Downloaded #{all_rows.size} total ADE rows from Hugging Face parquet (split: #{dataset.split})"
puts "   Using #{rows.size} shuffled examples for optimization"

examples = ADEExample.build_examples(rows)
puts "🧪 Prepared #{examples.size} DSPy examples"

# Validate class balance
positive_count = examples.count { |ex| ex.expected_values[:label].serialize == "1" }
negative_count = examples.size - positive_count
positive_pct = (positive_count.to_f / examples.size * 100).round(2)

if positive_count == 0 || negative_count == 0
  warn "❌ Dataset is imbalanced: #{positive_count} positive, #{negative_count} negative"
  warn "   Expected ~29% positive, ~71% negative. Check dataset loading."
  exit 1
end

puts "   • Positive (ADE): #{positive_count} (#{positive_pct}%)"
puts "   • Negative (Not ADE): #{negative_count} (#{(100 - positive_pct).round(2)}%)"

train_examples, val_examples, test_examples = ADEExample.split_examples(examples, train_ratio: 0.6, val_ratio: 0.2, seed: effective_seed)

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

# F1-aware metric that prioritizes balanced precision and recall
# Returns a score that approximates contribution to F1
metric = proc do |example, prediction|
  expected = example.expected_values[:label]
  predicted = ADEExample.label_from_prediction(prediction)

  is_ade = expected == ADEExample::ADETextClassifier::ADELabel::Related
  predicted_ade = predicted == ADEExample::ADETextClassifier::ADELabel::Related

  if is_ade && predicted_ade
    # True positive: contributes to both precision and recall
    1.0
  elsif !is_ade && !predicted_ade
    # True negative: correct but doesn't contribute to F1 for positive class
    0.5
  elsif is_ade && !predicted_ade
    # False negative: severely hurts recall (dangerous in medical screening)
    0.0
  else
    # False positive: hurts precision (less critical than FN)
    0.2
  end
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
optimizer.configure do |config|
  if options[:auto]
    config.auto_preset = DSPy::Teleprompt::AutoPreset.deserialize(options[:auto])
  else
    config.num_trials = options[:trials]
    config.num_instruction_candidates = 3
    config.bootstrap_sets = 2
    config.max_bootstrapped_examples = 2
    config.max_labeled_examples = 4
    config.optimization_strategy = :adaptive
  end
end

run_description =
  if options[:auto]
    "auto preset #{options[:auto]}"
  else
    "#{options[:trials]} trials"
  end

puts "\n🚀 Running MIPROv2 optimization (#{run_description})..."
overall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - overall_start
summary = {
  timestamp: Time.now.utc.iso8601,
  limit: options[:limit],
  trials: optimizer.config.num_trials,
  auto_preset: optimizer.config.auto_preset&.serialize,
  seed: effective_seed,
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
  optimization_strategy: result.history[:optimization_strategy],
  duration_seconds: elapsed_seconds
}

best_instruction_text = result.metadata[:best_instruction].to_s

if best_instruction_text.empty?
  best_trial = trial_logs.values.compact.max_by { |entry| entry[:score] || 0 }
  if best_trial && best_trial[:instructions]&.any?
    best_instruction_text = best_trial[:instructions].values.compact.first.to_s
  end
end

summary[:best_instruction] = best_instruction_text

timestamp_prefix = Time.now.utc.strftime('%Y%m%d%H%M%S')
summary_path = File.join(model_results_dir, "#{timestamp_prefix}_summary.json")
File.write(summary_path, JSON.pretty_generate(summary))

csv_path = File.join(model_results_dir, "#{timestamp_prefix}_metrics.csv")
CSV.open(csv_path, 'w') do |csv|
  csv << %w[metric baseline optimized]
  csv << ['accuracy', baseline_metrics.accuracy, optimized_metrics.accuracy]
  csv << ['precision', baseline_metrics.precision, optimized_metrics.precision]
  csv << ['recall', baseline_metrics.recall, optimized_metrics.recall]
  csv << ['f1', baseline_metrics.f1, optimized_metrics.f1]
end

trial_log_path = File.join(model_results_dir, "#{timestamp_prefix}_trial_logs.json")
serialized_trial_logs = serialize_trial_logs(trial_logs)
File.write(trial_log_path, JSON.pretty_generate(serialized_trial_logs))

puts "\n📂 Results saved to:"
puts "   • #{summary_path}"
puts "   • #{csv_path}"
puts "   • #{trial_log_path}"

puts "\n✨ Best instruction snippet:"
puts best_instruction_text.empty? ? '(no instruction recorded)' : best_instruction_text.lines.first.to_s.strip

puts "\n⏱️  Optimization completed in #{format('%.2f', elapsed_seconds)}s"
puts "\nDone!"
