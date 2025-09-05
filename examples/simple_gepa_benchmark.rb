#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple GEPA Benchmark - Ruby equivalent of the Python DSPy example
# This mirrors the exact structure from the Python screenshot

require_relative '../lib/dspy'
require 'benchmark'

# Skip if no API key available
unless ENV['OPENAI_API_KEY']
  puts "❌ OPENAI_API_KEY required for this benchmark"
  exit 1
end

# 1) Configure the base LM for generation
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
end

# 2) Simple signature equivalent to Python's 'q -> a'
class SimpleQASignature < DSPy::Signature
  description "Answer the question directly and concisely"
  
  input do
    const :q, String
  end
  
  output do
    const :a, String
  end
end

# 3) Exact-match metric (GEPA expects feedback format)
def create_exact_match_metric
  Class.new do
    include DSPy::Teleprompt::GEPAFeedbackMetric
    
    def call(example, prediction, trace = nil)
      expected = example.expected_values[:a]
      actual = prediction.a
      
      # Ruby DSPy.rb uses 3 args: example, prediction, trace
      # Python DSPy uses 5 args: gold, pred, trace, pred_name, pred_trace
      score = (expected == actual) ? 1.0 : 0.0
      feedback = score > 0 ? "Correct answer" : "Expected '#{expected}', got '#{actual}'"
      
      DSPy::Teleprompt::ScoreWithFeedback.new(
        score: score,
        prediction: prediction,
        feedback: feedback
      )
    end
  end.new
end

# Simple metric for MIPROv2 comparison
def simple_exact_match
  proc do |example, prediction|
    expected = example.expected_values[:a]
    actual = prediction.a
    (expected == actual) ? 1.0 : 0.0
  end
end

def run_simple_benchmark
  puts "🚀 Simple GEPA Benchmark (Ruby version of Python example)"
  puts "=" * 60
  
  # 3) Define the tiny program and a one-shot train example (like Python)
  program = DSPy::Predict.new(SimpleQASignature)
  trainset = [
    DSPy::Example.new(
      SimpleQASignature,
      input: { q: '2+2?' },
      expected: { a: '4' }
    )
  ]
  
  # Create a small validation set
  valset = [
    DSPy::Example.new(
      SimpleQASignature,
      input: { q: '3+3?' },
      expected: { a: '6' }
    ),
    DSPy::Example.new(
      SimpleQASignature,
      input: { q: '5-2?' },
      expected: { a: '3' }
    )
  ]
  
  puts "📊 Dataset:"
  puts "  Training examples: #{trainset.size}"
  puts "  Validation examples: #{valset.size}"
  puts
  
  # Test baseline
  puts "🔍 Testing baseline program:"
  baseline_result = program.call(q: '2+2?')
  puts "  Input: '2+2?'"
  puts "  Baseline output: '#{baseline_result.a}'"
  puts "  Expected: '4'"
  puts
  
  # Test baseline on validation set
  simple_metric = simple_exact_match
  baseline_score = valset.map do |example|
    pred = program.call(**example.input_values)
    simple_metric.call(example, pred)
  end.sum / valset.size.to_f
  
  puts "  Baseline validation accuracy: #{(baseline_score * 100).round(1)}%"
  puts
  
  # 4) Compare MIPROv2 vs GEPA
  exact_match_metric = create_exact_match_metric
  
  puts "⚡ Optimizing with MIPROv2..."
  mipro_start = Time.now
  
  begin
    mipro = DSPy::Teleprompt::MIPROv2.new(
      metric: simple_metric,
      num_candidates: 3,
      init_temperature: 1.0,
      verbose: false
    )
    
    mipro_optimized = mipro.compile(program, trainset: trainset, valset: valset)
    mipro_time = Time.now - mipro_start
    
    # Test MIPROv2 result
    mipro_result = mipro_optimized.call(q: '2+2?')
    puts "  MIPROv2 output: '#{mipro_result.a}'"
    puts "  Optimization time: #{mipro_time.round(2)}s"
    
    # Validate MIPROv2
    mipro_score = valset.map do |example|
      pred = mipro_optimized.call(**example.input_values)
      simple_metric.call(example, pred)
    end.sum / valset.size.to_f
    puts "  MIPROv2 validation accuracy: #{(mipro_score * 100).round(1)}%"
    
  rescue => e
    puts "  ❌ MIPROv2 failed: #{e.message}"
    mipro_optimized = program
    mipro_score = baseline_score
    mipro_time = 0
  end
  
  puts
  
  puts "🧬 Optimizing with GEPA..."
  gepa_start = Time.now
  
  begin
    # 4) Instantiate GEPA and compile (optimize) the program
    # Ruby DSPy.rb doesn't have auto='light' yet, so we configure manually
    config = DSPy::Teleprompt::GEPA::GEPAConfig.new
    config.reflection_lm = "openai/gpt-4o-mini"  # Equivalent to reflection_lm parameter
    config.population_size = 4  # Light mode - smaller population
    config.num_generations = 2  # Light mode - fewer generations
    config.mutation_rate = 0.8
    config.crossover_rate = 0.7
    
    gepa = DSPy::Teleprompt::GEPA.new(
      metric: exact_match_metric,
      config: config
    )
    
    gepa_optimized = gepa.compile(program, trainset: trainset, valset: valset)
    gepa_time = Time.now - gepa_start
    
    # 5) Run the optimized program
    gepa_result = gepa_optimized.call(q: '2+2?')
    puts "  GEPA output: '#{gepa_result.a}'"
    puts "  Optimization time: #{gepa_time.round(2)}s"
    
    # Validate GEPA
    gepa_score = valset.map do |example|
      pred = gepa_optimized.call(**example.input_values)
      simple_metric.call(example, pred)
    end.sum / valset.size.to_f
    puts "  GEPA validation accuracy: #{(gepa_score * 100).round(1)}%"
    
  rescue => e
    puts "  ❌ GEPA failed: #{e.message}"
    puts "  Error details: #{e.backtrace.first(3).join("\n  ")}" if ENV['DEBUG']
    gepa_optimized = program
    gepa_score = baseline_score
    gepa_time = 0
  end
  
  puts
  puts "📈 Final Results:"
  puts "=" * 40
  printf "  %-12s %10s %12s\n", "Method", "Accuracy", "Time (s)"
  puts "-" * 40
  printf "  %-12s %9.1f%% %11s\n", "Baseline", baseline_score * 100, "-"
  printf "  %-12s %9.1f%% %11.2f\n", "MIPROv2", mipro_score * 100, mipro_time
  printf "  %-12s %9.1f%% %11.2f\n", "GEPA", gepa_score * 100, gepa_time
  puts
  
  # Show which method performed better
  if gepa_score > mipro_score
    improvement = ((gepa_score - mipro_score) / [mipro_score, 0.01].max * 100).round(1)
    puts "🏆 GEPA wins with #{improvement}% improvement over MIPROv2!"
  elsif mipro_score > gepa_score  
    improvement = ((mipro_score - gepa_score) / [gepa_score, 0.01].max * 100).round(1)
    puts "🏆 MIPROv2 wins with #{improvement}% improvement over GEPA!"
  else
    puts "🤝 It's a tie!"
  end
  
  # Show optimized instructions if available
  puts
  puts "🔧 Instruction Evolution:"
  puts "Original: #{SimpleQASignature.description}"
  
  if mipro_optimized.respond_to?(:signature) && mipro_optimized.signature.respond_to?(:description)
    puts "MIPROv2:  #{mipro_optimized.signature.description}"
  end
  
  if gepa_optimized.respond_to?(:signature) && gepa_optimized.signature.respond_to?(:description)
    puts "GEPA:     #{gepa_optimized.signature.description}"
  end
  
  puts
  puts "✅ Simple GEPA benchmark completed!"
end

# Run the benchmark
if __FILE__ == $0
  run_simple_benchmark
end