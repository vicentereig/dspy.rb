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

# Telecomposing autopresets may surface few-shot examples as Hashes; convert to DSPy::FewShotExample for clarity.
module DSPy
  module Teleprompt
    class MIPROv2
      module HashFewShotNormalization
        def normalize_few_shot_examples(examples)
          super.map do |example|
            next example unless example.is_a?(Hash)

            input = example[:input] || example['input'] || {}
            output = example[:expected] || example['expected'] || example[:output] || example['output'] || {}
            reasoning = example[:reasoning] || example['reasoning']

            DSPy::FewShotExample.new(input: input, output: output, reasoning: reasoning)
          end
        end
      end

      prepend HashFewShotNormalization
    end
  end
end

module ADEOptimizationDemo
  EXAMPLE_ROOT = File.expand_path(__dir__)
  DATA_DIR = File.join(EXAMPLE_ROOT, 'data')
  RESULTS_DIR = File.join(EXAMPLE_ROOT, 'results')
  DATASET_CACHE_DIR = File.join(DATA_DIR, 'ade_parquet')
  DSPY_DATASET_ID = 'ade-benchmark-corpus/ade_corpus_v2'
  AUTO_PRESET_CHOICES = %w[light medium heavy none].freeze

  Options = Struct.new(
    :limit,
    :trials,
    :auto,
    :model,
    :seed,
    keyword_init: true
  )

  module_function

  def run(argv)
    FileUtils.mkdir_p(DATA_DIR)
    FileUtils.mkdir_p(RESULTS_DIR)
    FileUtils.mkdir_p(DATASET_CACHE_DIR)

    options = parse_options(argv)
    provider, env_var, api_key = resolve_model_credentials(options.model)
    check_api_key!(provider, env_var, api_key, options.model)

    configure_dspy(options.model, api_key)

    puts '🏥 ADE MIPROv2 Optimization Demo'
    puts '================================'
    effective_seed = options.seed || Random.new_seed
    print_run_configuration(options, effective_seed)

    train_examples, val_examples, test_examples = load_dataset(options.limit, effective_seed)
    baseline_program = DSPy::Predict.new(ADEExample::ADETextClassifier)
    baseline_metrics = ADEExample.evaluate(baseline_program, test_examples)
    report_baseline_metrics(baseline_metrics)

    metric = build_metric

    optimizer = build_optimizer(metric, options)
    puts "\n🚀 Running MIPROv2 optimization (#{run_description(options)})..."

    overall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = optimizer.compile(baseline_program, trainset: train_examples, valset: val_examples)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - overall_start

    optimized_program = result.optimized_program
    optimized_metrics = ADEExample.evaluate(optimized_program, test_examples)
    report_optimized_metrics(optimized_metrics, baseline_metrics)

    trial_logs = (result.optimization_trace[:trial_logs] || {})
    display_trial_logs(trial_logs)
    best_instruction = extract_best_instruction(result, trial_logs)

    summary_path, csv_path, trial_log_path = persist_results(
      provider,
      options.model,
      optimizer,
      options,
      effective_seed,
      baseline_metrics,
      optimized_metrics,
      result,
      duration,
      trial_logs,
      best_instruction
    )

    print_result_paths(summary_path, csv_path, trial_log_path)
    print_best_instruction(best_instruction)
    puts "\n⏱️  Optimization completed in #{format('%.2f', duration)}s"
    puts "\nDone!"
  end

  def parse_options(argv)
    options = Options.new(
      limit: 300,
      trials: 6,
      auto: nil,
      model: 'openai/gpt-5-2025-08-07',
      seed: nil
    )

    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: bundle exec ruby examples/ade_optimizer_miprov2/main.rb [options]'

      opts.on('-l', '--limit N', Integer, 'Number of ADE examples to download (default: 300)') do |limit|
        options.limit = limit
      end

      opts.on('-t', '--trials N', Integer, 'Number of MIPROv2 trials (default: 6)') do |trials|
        options.trials = trials
      end

      opts.on('--auto MODE', String, "Auto preset (#{AUTO_PRESET_CHOICES.join(', ')})") do |mode|
        normalized = mode.strip.downcase
        unless AUTO_PRESET_CHOICES.include?(normalized)
          raise OptionParser::InvalidArgument, "invalid auto preset '#{mode}'. Must be one of #{AUTO_PRESET_CHOICES.join(', ')}"
        end
        options.auto = normalized
      end

      opts.on('--model ID', String,
              'Fully-qualified model ID (default: openai/gpt-5-2025-08-07)') do |model_id|
        options.model = model_id.strip
      end

      opts.on('--seed N', Integer, 'Random seed for dataset splits (default: random)') do |seed|
        options.seed = seed
      end

      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        exit
      end
    end

    parser.parse!(argv)
    options.auto = nil if options.auto == 'none'
    ensure_model_format!(options.model)
    options
  rescue OptionParser::ParseError => e
    warn "❌ #{e.message}"
    warn parser
    exit 1
  end

  def ensure_model_format!(model)
    return if model.include?('/')

    warn "⚠️  Invalid model '#{model}'. Please use the format provider/model (e.g., openai/gpt-4o-mini)."
    exit 1
  end

  def resolve_model_credentials(model_id)
    provider = model_id.to_s.split('/', 2).first
    env_var =
      case provider
      when 'openai' then 'OPENAI_API_KEY'
      when 'anthropic' then 'ANTHROPIC_API_KEY'
      when 'gemini' then 'GEMINI_API_KEY'
      else
        provider&.upcase&.gsub(/[^A-Z0-9]/, '_')&.then { |value| "#{value}_API_KEY" }
      end
    [provider, env_var, env_var ? ENV[env_var] : nil]
  end

  def check_api_key!(provider, env_var, api_key, model)
    return unless api_key.to_s.strip.empty?

    warn "⚠️  Please set #{env_var || 'the appropriate *_API_KEY variable'} in your environment before running this example (model: #{model})."
    exit 1
  end

  def configure_dspy(model_id, api_key)
    DSPy.configure do |config|
      config.lm = DSPy::LM.new(model_id, api_key: api_key)
      config.logger = Dry.Logger(:dspy, formatter: :string) do |logger|
        logger.add_backend(stream: File.join(EXAMPLE_ROOT, '../../log/dspy_ade_example.log'))
      end
    end
  end

  def print_run_configuration(options, seed)
    puts "Limit       : #{options.limit}"
    if options.auto
      puts "Auto Preset : #{options.auto.capitalize}"
    else
      puts "Trials      : #{options.trials}"
    end
    puts "Model       : #{options.model}"
    puts "Random Seed : #{seed}"
  end

  def load_dataset(limit, seed)
    dataset = DSPy::Datasets.fetch(DSPY_DATASET_ID, split: 'train', cache_dir: DATASET_CACHE_DIR)
    all_rows = dataset.rows

    if all_rows.empty?
      warn "❌ Failed to download ADE dataset rows. Please check your network connection."
      exit 1
    end

    shuffled_rows = all_rows.shuffle(random: Random.new(seed))
    rows = shuffled_rows.first(limit)

    puts "\n📦 Downloaded #{all_rows.size} total ADE rows from Hugging Face parquet (split: #{dataset.split})"
    puts "   Using #{rows.size} shuffled examples for optimization"

    examples = ADEExample.build_examples(rows)
    puts "🧪 Prepared #{examples.size} DSPy examples"

    validate_balance!(examples)

    train_examples, val_examples, test_examples = ADEExample.split_examples(
      examples,
      train_ratio: 0.6,
      val_ratio: 0.2,
      seed: seed
    )

    puts '📊 Dataset split:'
    puts "   • Train: #{train_examples.size}"
    puts "   • Val  : #{val_examples.size}"
    puts "   • Test : #{test_examples.size}"

    [train_examples, val_examples, test_examples]
  end

  def validate_balance!(examples)
    positive_count = examples.count { |ex| ex.expected_values[:label].serialize == '1' }
    negative_count = examples.size - positive_count
    positive_pct = (positive_count.to_f / examples.size * 100).round(2)

    if positive_count.zero? || negative_count.zero?
      warn "❌ Dataset is imbalanced: #{positive_count} positive, #{negative_count} negative"
      warn '   Expected ~29% positive, ~71% negative. Check dataset loading.'
      exit 1
    end

    puts "   • Positive (ADE): #{positive_count} (#{positive_pct}%)"
    puts "   • Negative (Not ADE): #{negative_count} (#{(100 - positive_pct).round(2)}%)"
  end

  def report_baseline_metrics(metrics)
    puts "\n🔎 Baseline evaluation"
    puts "   • Accuracy : #{(metrics.accuracy * 100).round(2)}%"
    puts "   • Precision: #{(metrics.precision * 100).round(2)}%"
    puts "   • Recall   : #{(metrics.recall * 100).round(2)}%"
    puts "   • F1 Score : #{(metrics.f1 * 100).round(2)}%"
  end

  def build_metric
    proc do |example, prediction|
      expected = example.expected_values[:label]
      predicted = ADEExample.label_from_prediction(prediction)

      is_ade = expected == ADEExample::ADETextClassifier::ADELabel::Related
      predicted_ade = predicted == ADEExample::ADETextClassifier::ADELabel::Related

      if is_ade && predicted_ade
        1.0
      elsif !is_ade && !predicted_ade
        0.5
      elsif is_ade && !predicted_ade
        0.0
      else
        0.2
      end
    end
  end

  def build_optimizer(metric, options)
    optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
    optimizer.configure do |config|
      if options.auto
        config.auto_preset = DSPy::Teleprompt::AutoPreset.deserialize(options.auto)
      else
        config.num_trials = options.trials
        config.num_instruction_candidates = 3
        config.bootstrap_sets = 2
        config.max_bootstrapped_examples = 2
        config.max_labeled_examples = 4
        config.optimization_strategy = :adaptive
      end
    end
    optimizer
  end

  def run_description(options)
    if options.auto
      "auto preset #{options.auto}"
    else
      "#{options.trials} trials"
    end
  end

  def report_optimized_metrics(optimized_metrics, baseline_metrics)
    puts "\n🏁 Optimized program performance:"
    puts "   • Accuracy : #{(optimized_metrics.accuracy * 100).round(2)}%"
    puts "   • Precision: #{(optimized_metrics.precision * 100).round(2)}%"
    puts "   • Recall   : #{(optimized_metrics.recall * 100).round(2)}%"
    puts "   • F1 Score : #{(optimized_metrics.f1 * 100).round(2)}%"

    improvement = (optimized_metrics.accuracy - baseline_metrics.accuracy) * 100
    puts "\n📣 Accuracy improvement: #{improvement.round(2)} percentage points"
  end

  def display_trial_logs(trial_logs)
    return if trial_logs.empty?

    puts "\n📝 Trial-by-trial instruction snapshots:"
    trial_logs.sort.each do |trial_number, entry|
      instructions = entry[:instructions]
      next unless instructions

      puts "\n  Trial ##{trial_number}:"
      instructions.each do |predictor_index, instruction|
        puts "    • Predictor #{predictor_index}: #{instruction || '(no instruction)'}"
      end
    end
  end

  def extract_best_instruction(result, trial_logs)
    best_instruction_text = result.metadata[:best_instruction].to_s
    return best_instruction_text unless best_instruction_text.empty?

    best_trial = trial_logs.values.compact.max_by { |entry| entry[:score] || 0 }
    if best_trial && best_trial[:instructions]&.any?
      best_trial[:instructions].values.compact.first.to_s
    else
      ''
    end
  end

  def persist_results(provider, model_id, optimizer, options, seed, baseline_metrics, optimized_metrics, result, duration, trial_logs, best_instruction)
    sanitized_provider = (provider || 'unknown').gsub(/[^A-Za-z0-9._-]/, '_')
    raw_model_identifier = model_id.split('/', 2).last || model_id
    sanitized_model_identifier = raw_model_identifier.gsub(/[^A-Za-z0-9._-]/, '_')
    model_results_dir = File.join(RESULTS_DIR, sanitized_provider, sanitized_model_identifier)
    FileUtils.mkdir_p(model_results_dir)

    timestamp_prefix = Time.now.utc.strftime('%Y%m%d%H%M%S')

    summary = {
      timestamp: Time.now.utc.iso8601,
      limit: options.limit,
      trials: optimizer.config.num_trials,
      auto_preset: optimizer.config.auto_preset&.serialize,
      seed: seed,
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
      best_instruction: best_instruction,
      total_trials: result.history[:total_trials],
      optimization_strategy: result.history[:optimization_strategy],
      duration_seconds: duration
    }

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

    [summary_path, csv_path, trial_log_path]
  end

  def serialize_trial_logs(trial_logs)
    trial_logs.transform_values { |entry| serialize_few_shot_payload(entry) }
  end

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

  def print_result_paths(summary_path, csv_path, trial_log_path)
    puts "\n📂 Results saved to:"
    puts "   • #{summary_path}"
    puts "   • #{csv_path}"
    puts "   • #{trial_log_path}"
  end

  def print_best_instruction(best_instruction)
    puts "\n✨ Best instruction snippet:"
    puts best_instruction.empty? ? '(no instruction recorded)' : best_instruction.lines.first.to_s.strip
  end
end

ADEOptimizationDemo.run(ARGV)
