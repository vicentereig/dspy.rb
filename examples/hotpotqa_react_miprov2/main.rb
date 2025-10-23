#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'optparse'
require 'set'
require 'fileutils'

require 'dspy'
require 'dspy/datasets'

module HotPotQAReActDemo
  EXAMPLE_ROOT = File.expand_path(__dir__)
  DATA_DIR = File.join(EXAMPLE_ROOT, 'data')
  CACHE_DIR = File.join(DATA_DIR, 'hotpotqa_parquet')

  Options = Struct.new(
    :train_size,
    :dev_size,
    :test_size,
    :auto,
    :seed,
    :max_iterations,
    :threads,
    keyword_init: true
  )

  module_function

  def run(argv)
    FileUtils.mkdir_p(CACHE_DIR)
    options = parse_options(argv)
    ensure_openai_key!

    configure_dspy

    puts '🧠 HotPotQA ReAct + MIPROv2 Example'
    puts '===================================='
    print_run_configuration(options)

    dataset = load_dataset(options)
    context_tool = HotPotQAContextTool.new(lookup: dataset.context_lookup.transform_keys(&:dup))

    train_examples = build_examples(dataset.train.first(options.train_size))
    dev_examples = build_examples(dataset.dev.first(options.dev_size))
    test_examples = build_examples(dataset.test.first(options.test_size))
    show_dataset_summary(train_examples, dev_examples, test_examples)

    react_agent = DSPy::ReAct.new(
      HotPotQASignature,
      tools: [context_tool],
      max_iterations: options.max_iterations
    )

    metric = build_metric

    baseline_accuracy = evaluate_accuracy(react_agent, dev_examples, metric, options.threads)
    puts "\n🔎 Baseline evaluation"
    puts "Validation accuracy: #{format('%.2f', baseline_accuracy * 100)}%"

    optimizer = build_optimizer(metric, options)
    puts "\n🚀 Running MIPROv2 optimization (this may take several minutes)..."
    result = optimizer.compile(react_agent, trainset: train_examples, valset: dev_examples)

    optimized_agent = result.optimized_program || react_agent
    optimized_accuracy = evaluate_accuracy(optimized_agent, dev_examples, metric, options.threads)
    test_accuracy = evaluate_accuracy(optimized_agent, test_examples, metric, options.threads)

    report_results(result, optimized_accuracy, test_accuracy)
    print_prompt_details(optimized_agent)
  end

  def parse_options(argv)
    options = Options.new(
      train_size: 300,
      dev_size: 100,
      test_size: 100,
      auto: 'light',
      seed: 2024,
      max_iterations: 5,
      threads: 8
    )

    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: bundle exec ruby examples/hotpotqa_react_miprov2/main.rb [options]'

      opts.on('--train N', Integer, 'Number of train examples (default: 300)') { |value| options.train_size = value }
      opts.on('--dev N', Integer, 'Number of dev examples (default: 100)') { |value| options.dev_size = value }
      opts.on('--test N', Integer, 'Number of test examples (default: 100)') { |value| options.test_size = value }
      opts.on('--auto MODE', String, 'Auto preset (light, medium, heavy, none) (default: light)') { |value| options.auto = value }
      opts.on('--seed N', Integer, 'Random seed for dataset split (default: 2024)') { |value| options.seed = value }
      opts.on('--threads N', Integer, 'Number of threads for evaluation/optimization (default: 8)') { |value| options.threads = value }
      opts.on('--iterations N', Integer, 'Max ReAct iterations per question (default: 5)') { |value| options.max_iterations = value }
      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        exit 0
      end
    end

    parser.parse!(argv)
    options.auto = nil if options.auto&.casecmp('none')&.zero?
    options
  rescue OptionParser::ParseError => e
    warn "❌ #{e.message}"
    warn parser
    exit 1
  end

  def ensure_openai_key!
    return if ENV['OPENAI_API_KEY']

    warn '⚠️  Please set OPENAI_API_KEY before running this example.'
    exit 1
  end

  def configure_dspy
    DSPy.configure do |config|
      config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      config.logger = Dry.Logger(:dspy, formatter: :string) do |logger|
        logger.add_backend(stream: File.join(EXAMPLE_ROOT, '../../log/dspy_hotpotqa.log'))
      end
    end
  end

  def print_run_configuration(options)
    puts "Train size : #{options.train_size}"
    puts "Dev size   : #{options.dev_size}"
    puts "Test size  : #{options.test_size}"
    puts "Auto preset: #{options.auto || 'manual'}"
    puts "Seed       : #{options.seed}"
    puts
  end

  def load_dataset(options)
    puts '📦 Downloading HotPotQA splits from Hugging Face (parquet)...'
    DSPy::Datasets::HotPotQA.new(
      train_seed: options.seed,
      train_size: options.train_size && options.train_size * 2,
      dev_size: options.dev_size && options.dev_size * 2,
      test_size: options.test_size && options.test_size * 2,
      cache_dir: CACHE_DIR
    )
  end

  def build_examples(rows)
    rows.map do |row|
      DSPy::Example.new(
        signature_class: HotPotQASignature,
        input: { question: row[:question] },
        expected: { answer: row[:answer] },
        id: row[:id]
      )
    end
  end

  def show_dataset_summary(train_examples, dev_examples, test_examples)
    total = train_examples.size + dev_examples.size + test_examples.size
    puts "✅ Prepared #{total} examples (train=#{train_examples.size}, dev=#{dev_examples.size}, test=#{test_examples.size})"
  end

  def build_metric
    proc do |example, prediction|
      expected = normalize(example.expected_values[:answer])
      predicted = if prediction.respond_to?(:answer)
        normalize(prediction.answer)
      else
        normalize(prediction[:answer] || prediction['answer'])
      end

      !expected.empty? && predicted.include?(expected)
    end
  end

  def build_optimizer(metric, options)
    if options.auto
      preset = options.auto.downcase
      builders = {
        'light' => DSPy::Teleprompt::MIPROv2::AutoMode.method(:light),
        'medium' => DSPy::Teleprompt::MIPROv2::AutoMode.method(:medium),
        'heavy' => DSPy::Teleprompt::MIPROv2::AutoMode.method(:heavy)
      }
      builder = builders[preset]
      raise OptionParser::InvalidArgument, "Unsupported auto preset '#{options.auto}'. Choose light, medium, heavy, or none." unless builder
      builder.call(metric: metric)
    else
      DSPy::Teleprompt::MIPROv2.new(metric: metric).tap do |opt|
        opt.configure do |config|
          config.num_trials = 8
          config.num_instruction_candidates = 4
          config.bootstrap_sets = 3
          config.max_bootstrapped_examples = 3
          config.max_labeled_examples = 6
          config.optimization_strategy = :adaptive
        end
      end
    end.tap do |optimizer|
      optimizer.configure do |config|
        config.num_threads = options.threads
      end
    end
  end

  def evaluate_accuracy(program, examples, metric, threads)
    evaluator = DSPy::Evals.new(program, metric: metric, num_threads: threads)
    result = evaluator.evaluate(examples, display_progress: false, display_table: false)
    result.pass_rate
  end

  def report_results(result, optimized_accuracy, test_accuracy)
    puts "\n✨ Optimized dev accuracy: #{(optimized_accuracy * 100).round(2)}%"
    puts "🎯 Test accuracy: #{(test_accuracy * 100).round(2)}%"

    puts "\n📋 Best trial summary:"
    puts "   • Score              : #{(result.best_score_value * 100).round(2)}%"
    puts "   • Trials completed   : #{result.history[:total_trials]}"
    puts "   • Best candidate type: #{result.metadata[:best_candidate_type]}"
    puts "   • Few-shot examples  : #{result.metadata[:best_few_shot_count]}"
  end

  def print_prompt_details(agent)
    return unless agent.respond_to?(:prompt)

    prompt = agent.prompt
    puts "\n📝 Optimized instruction:"
    puts prompt.instruction

    unless prompt.few_shot_examples.empty?
      puts "\n📚 Few-shot examples:"
      prompt.few_shot_examples.each_with_index do |example, index|
        puts "--- Example #{index + 1} ---"
        puts example.to_prompt_section
      end
    end
  end

  def normalize(text)
    text.to_s.strip.downcase
  end

  class HotPotQAContextTool < DSPy::Tools::Base
    tool_name 'hotpot_context'
    tool_description 'Retrieve supporting paragraphs for a HotPotQA question'

    def initialize(lookup:)
      @lookup = lookup
    end

    def call(question:)
      contexts = @lookup.fetch(question, [])
      return 'No supporting facts available.' if contexts.empty?

      contexts.first(2).join("\n")
    end
  end

  class HotPotQASignature < DSPy::Signature
    description 'Answer HotPotQA multi-hop questions concisely.'

    input do
      const :question, String, description: 'HotPotQA question to answer'
    end

    output do
      const :answer, String, description: 'Concise final answer (single phrase)'
    end
  end
end

HotPotQAReActDemo.run(ARGV)
