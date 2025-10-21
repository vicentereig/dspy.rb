#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv/load'
require 'optparse'
require 'set'
require 'fileutils'

require 'dspy'
require 'dspy/datasets'

def evaluate_accuracy(program, examples, metric, threads)
  evaluator = DSPy::Evaluate.new(program, metric: metric, num_threads: threads)
  result = evaluator.batch(examples)
  result.pass_rate
end

EXAMPLE_ROOT = File.expand_path(__dir__)
DATA_DIR = File.join(EXAMPLE_ROOT, 'data')
CACHE_DIR = File.join(DATA_DIR, 'hotpotqa_parquet')
FileUtils.mkdir_p(CACHE_DIR)

options = {
  train_size: 300,
  dev_size: 100,
  test_size: 100,
  auto: 'light',
  seed: 2024,
  max_iterations: 5,
  threads: 8
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: bundle exec ruby examples/hotpotqa_react_miprov2/main.rb [options]'

  opts.on('--train N', Integer, 'Number of train examples (default: 300)') { |value| options[:train_size] = value }
  opts.on('--dev N', Integer, 'Number of dev examples (default: 100)') { |value| options[:dev_size] = value }
  opts.on('--test N', Integer, 'Number of test examples (default: 100)') { |value| options[:test_size] = value }
  opts.on('--auto MODE', String, 'Auto preset (light, medium, heavy, none) (default: light)') { |value| options[:auto] = value }
  opts.on('--seed N', Integer, 'Random seed for dataset split (default: 2024)') { |value| options[:seed] = value }
  opts.on('--threads N', Integer, 'Number of threads for evaluation/optimization (default: 8)') { |value| options[:threads] = value }
  opts.on('--iterations N', Integer, 'Max ReAct iterations per question (default: 5)') { |value| options[:max_iterations] = value }
  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "❌ #{e.message}"
  warn parser
  exit 1
end

options[:auto] = nil if options[:auto]&.casecmp('none')&.zero?

unless ENV['OPENAI_API_KEY']
  warn '⚠️  Please set OPENAI_API_KEY before running this example.'
  exit 1
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  config.logger = Dry.Logger(:dspy, formatter: :string) do |logger|
    logger.add_backend(stream: File.join(EXAMPLE_ROOT, '../../log/dspy_hotpotqa.log'))
  end
end

class HotPotQAContextTool < DSPy::Tools::Base
  tool_name 'hotpot_context'
  tool_description 'Retrieve supporting paragraphs for a HotPotQA question'

  extend T::Sig

  sig { params(question: String).returns(String) }
  def call(question:)
    contexts = @lookup.fetch(question, [])
    return 'No supporting facts available.' if contexts.empty?

    contexts.first(2).join("\n")
  end

  sig { params(lookup: T::Hash[String, T::Array[String]]).void }
  def initialize(lookup:)
    @lookup = lookup
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

puts '🧠 HotPotQA ReAct + MIPROv2 Example'
puts '===================================='
puts "Train size : #{options[:train_size]}"
puts "Dev size   : #{options[:dev_size]}"
puts "Test size  : #{options[:test_size]}"
puts "Auto preset: #{options[:auto] || 'manual'}"
puts "Seed       : #{options[:seed]}"
puts

puts '📦 Downloading HotPotQA splits from Hugging Face (parquet)...'
dataset = DSPy::Datasets::HotPotQA.new(
  train_seed: options[:seed],
  train_size: options[:train_size] && options[:train_size] * 2,
  dev_size: options[:dev_size] && options[:dev_size] * 2,
  test_size: options[:test_size] && options[:test_size] * 2,
  cache_dir: CACHE_DIR
)

train_rows = dataset.train.first(options[:train_size])
dev_rows = dataset.dev.first(options[:dev_size])
test_rows = dataset.test.first(options[:test_size])

total_rows = train_rows.size + dev_rows.size + test_rows.size
puts "✅ Prepared #{total_rows} examples (train=#{train_rows.size}, dev=#{dev_rows.size}, test=#{test_rows.size})"

context_lookup = dataset.context_lookup.transform_keys(&:dup)
context_tool = HotPotQAContextTool.new(lookup: context_lookup)

train_examples = build_examples(train_rows)
dev_examples = build_examples(dev_rows)
test_examples = build_examples(test_rows)

react_agent = DSPy::ReAct.new(HotPotQASignature, tools: [context_tool], max_iterations: options[:max_iterations])

metric = proc do |example, prediction|
  expected = example.expected_values[:answer].to_s.strip.downcase
  predicted = prediction.respond_to?(:answer) ? prediction.answer.to_s.strip.downcase : ''
  !expected.empty? && predicted.include?(expected)
end

baseline_accuracy = evaluate_accuracy(react_agent, dev_examples, metric, options[:threads])
puts "\n📈 Baseline dev accuracy without optimization: #{(baseline_accuracy * 100).round(2)}%"

optimizer = if options[:auto]
  preset = options[:auto].downcase
  builders = {
    'light' => DSPy::Teleprompt::MIPROv2::AutoMode.method(:light),
    'medium' => DSPy::Teleprompt::MIPROv2::AutoMode.method(:medium),
    'heavy' => DSPy::Teleprompt::MIPROv2::AutoMode.method(:heavy)
  }
  builder = builders[preset]
  raise ArgumentError, "Unsupported auto preset '#{options[:auto]}'. Choose light, medium, heavy, or none." unless builder
  builder.call(metric: metric)
else
  DSPy::Teleprompt::MIPROv2.new(metric: metric)
end

optimizer.configure do |config|
  config.num_threads = options[:threads]
  unless options[:auto]
    config.num_trials = 8
    config.num_instruction_candidates = 4
    config.bootstrap_sets = 3
    config.max_bootstrapped_examples = 3
    config.max_labeled_examples = 6
    config.optimization_strategy = :adaptive
  end
end

puts "\n🚀 Running MIPROv2 optimization (this may take several minutes)..."
result = optimizer.compile(react_agent, trainset: train_examples, valset: dev_examples)

optimized_agent = result.optimized_program || react_agent
optimized_accuracy = evaluate_accuracy(optimized_agent, dev_examples, metric, options[:threads])
puts "\n✨ Optimized dev accuracy: #{(optimized_accuracy * 100).round(2)}%"

test_accuracy = evaluate_accuracy(optimized_agent, test_examples, metric, options[:threads])
puts "🎯 Test accuracy: #{(test_accuracy * 100).round(2)}%"

puts "\n📋 Best trial summary:"
puts "   • Score              : #{(result.best_score_value * 100).round(2)}%"
puts "   • Trials completed   : #{result.history[:total_trials]}"
puts "   • Best candidate type: #{result.metadata[:best_candidate_type]}"
puts "   • Few-shot examples  : #{result.metadata[:best_few_shot_count]}"

if optimized_agent.respond_to?(:prompt)
  prompt = optimized_agent.prompt
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
