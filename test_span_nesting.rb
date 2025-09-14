#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative 'lib/dspy'

# Configure basic signature for testing
class TestSignature < DSPy::Signature
  description "Test signature for span nesting"
  
  input do
    const :query, String
  end
  
  output do
    const :response, String
  end
end

# Configure observability
DSPy::Observability.configure!

# Configure a mock LM to avoid real API calls
class MockLM
  def initialize
    @model_id = "mock/test"
    @provider = "mock"
    @model = "test"
  end
  
  attr_reader :model_id, :provider, :model
  
  def chat(inference_module, input_values)
    puts "🔍 MockLM.chat called with: #{input_values}"
    
    # Simulate the real LM's instrumentation
    signature_class = inference_module.signature_class
    
    # This should create an 'llm.generate' span nested under the DSPy::Predict.forward span
    response = DSPy::Context.with_span(
      operation: 'llm.generate',
      'langfuse.observation.type' => 'generation',
      'gen_ai.system' => provider,
      'gen_ai.request.model' => model,
      'dspy.signature' => signature_class.name
    ) do |span|
      puts "  🎯 Inside llm.generate span"
      
      # Mock response
      result = {
        response: "Mock response for: #{input_values[:query]}"
      }
      
      if span
        span.set_attribute('langfuse.observation.output', result.to_json)
      end
      
      result
    end
    
    response
  end
end

# Configure DSPy to use mock LM
DSPy.configure do |config|
  config.lm = MockLM.new
end

puts "🚀 Testing span nesting..."
puts "Expected: DSPy::Predict.forward should contain llm.generate as a child span"
puts

# Create predictor and test
predictor = DSPy::Predict.new(TestSignature)

# This should create a 'DSPy::Predict.forward' span with nested 'llm.generate' span
result = predictor.call(query: "Test query for span nesting")

puts "✅ Test completed"
puts "📊 Result: #{result.response}"
puts
puts "🔍 Check Langfuse traces to see if spans are properly nested:"
puts "- Expected: DSPy::Predict.forward (parent)"
puts "  - llm.generate (child)"
puts 
puts "🚨 If they appear as separate root traces, we have the orphaned spans issue!"

# Flush observability data
DSPy::Observability.flush!