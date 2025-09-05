#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal GEPA test - Ruby equivalent of Python example
require_relative '../../lib/dspy'
require 'dotenv'
Dotenv.load(File.join(File.dirname(__FILE__), '..', '..', '.env'))

# Skip if no API key available
unless ENV['OPENAI_API_KEY']
  puts "❌ OPENAI_API_KEY required for this test"
  exit 1
end

# 1) Configure the base LM for generation
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
end

# 2) Simple signature equivalent to Python's 'q -> a'
class QASignature < DSPy::Signature
  description "Answer the question"
  
  input do
    const :q, String
  end
  
  output do 
    const :a, String
  end
end

# Define simple metric (proc format expected by GEPA)
def create_test_metric
  proc do |example, prediction|
    expected = example.expected_values[:a]
    actual = prediction.a
    expected == actual ? 1.0 : 0.0
  end
end

def test_gepa_minimal
  puts "🧪 Testing GEPA with minimal example (like Python)..."
  puts "program = DSPy::Predict.new(QASignature)"
  puts "trainset = [DSPy::Example.new(..., q='2+2?', a='4')]"
  puts
  
  # 3) Define the tiny program and a one-shot train example
  program = DSPy::Predict.new(QASignature)
  trainset = [
    DSPy::Example.new(signature_class: QASignature, input: { q: '2+2?' }, expected: { a: '4' })
  ]
  
  # Add validation set
  valset = [
    DSPy::Example.new(signature_class: QASignature, input: { q: '3+3?' }, expected: { a: '6' })
  ]
  
  metric = create_test_metric
  
  # Test baseline
  baseline_result = program.call(q: '2+2?')
  puts "Baseline result: #{baseline_result.a}"
  
  # Test GEPA with minimal settings
  config = DSPy::Teleprompt::GEPA::GEPAConfig.new
  config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
  config.population_size = 2  # Light mode
  config.num_generations = 1  # Light mode
  
  gepa = DSPy::Teleprompt::GEPA.new(
    metric: metric,
    config: config
  )
  
  puts "Running GEPA optimization..."
  optimization_result = gepa.compile(program, trainset: trainset, valset: valset)
  
  # Test optimized result
  optimized = optimization_result.optimized_program
  optimized_result = optimized.call(q: '2+2?')
  puts "Optimized result: #{optimized_result.a}"
  
  puts "✅ GEPA minimal test completed!"
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5) if ENV['DEBUG']
end

test_gepa_minimal if __FILE__ == $0