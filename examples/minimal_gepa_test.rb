#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal GEPA test - Ruby equivalent of Python example
require_relative '../lib/dspy'

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

# Define metric with feedback
def create_test_metric
  Class.new do
    include DSPy::Teleprompt::GEPAFeedbackMetric
    
    def call(example, prediction, trace = nil)
      expected = example.expected_values[:a]
      actual = prediction.a
      
      score = expected == actual ? 1.0 : 0.0
      feedback = score > 0 ? "Correct" : "Expected #{expected}, got #{actual}"
      
      DSPy::Teleprompt::ScoreWithFeedback.new(
        score: score,
        prediction: prediction,
        feedback: feedback
      )
    end
  end.new
end

def test_gepa_minimal
  puts "🧪 Testing GEPA with minimal example (like Python)..."
  puts "program = DSPy::Predict.new(QASignature)"
  puts "trainset = [DSPy::Example.new(..., q='2+2?', a='4')]"
  puts
  
  # 3) Define the tiny program and a one-shot train example
  program = DSPy::Predict.new(QASignature)
  trainset = [
    DSPy::Example.new(QASignature, input: { q: '2+2?' }, expected: { a: '4' })
  ]
  
  metric = create_test_metric
  
  # Test baseline
  baseline_result = program.call(q: '2+2?')
  puts "Baseline result: #{baseline_result.a}"
  
  # Test GEPA with minimal settings
  config = DSPy::Teleprompt::GEPA::GEPAConfig.new
  config.reflection_lm = "openai/gpt-4o-mini"
  config.population_size = 2  # Light mode
  config.num_generations = 1  # Light mode
  
  gepa = DSPy::Teleprompt::GEPA.new(
    metric: metric,
    config: config
  )
  
  puts "Running GEPA optimization..."
  optimized = gepa.compile(program, trainset: trainset)
  
  # Test optimized result
  optimized_result = optimized.call(q: '2+2?')
  puts "Optimized result: #{optimized_result.a}"
  
  puts "✅ GEPA minimal test completed!"
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5) if ENV['DEBUG']
end

test_gepa_minimal if __FILE__ == $0