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

# Create a real LM instance with mock adapter to test the actual flow
class DebugLM < DSPy::LM
  def initialize
    super("debug/test", api_key: "fake")
  end
  
  private
  
  def create_adapter
    # Mock adapter that just returns test data
    adapter = Object.new
    def adapter.chat(messages:, signature: nil, &block)
      # Return a simple response object
      response_struct = Struct.new(:content, :usage, :metadata)
      usage_struct = Struct.new(:input_tokens, :output_tokens, :total_tokens)
      
      response_struct.new(
        '{"response": "Test response"}',
        usage_struct.new(10, 5, 15),
        nil
      )
    end
    adapter
  end
end

# Override the adapter creation method
module DSPy
  class LM
    private
    
    alias_method :original_create_adapter, :adapter
    attr_writer :adapter
    
    def adapter
      @adapter ||= create_mock_adapter
    end
    
    def create_mock_adapter
      adapter = Object.new
      def adapter.chat(messages:, signature: nil, &block)
        response_struct = Struct.new(:content, :usage, :metadata)
        usage_struct = Struct.new(:input_tokens, :output_tokens, :total_tokens)
        
        response_struct.new(
          '{"response": "Mock LM response"}',
          usage_struct.new(10, 5, 15),
          nil
        )
      end
      adapter
    end
  end
end

# Configure DSPy to use mock OpenAI LM
debug_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: "fake-key-for-testing")
DSPy.configure do |config|
  config.lm = debug_lm
end

puts "🔍 Testing context propagation fix with real DSPy::Predict -> LM flow..."
puts

# Track span creation for debugging
original_with_span = DSPy::Context.method(:with_span)
span_calls = []

DSPy::Context.define_singleton_method(:with_span) do |operation:, **attributes, &block|
  puts "🎯 Creating span: #{operation}"
  
  # Track this span call
  span_calls << {
    operation: operation, 
    attributes: attributes,
    context_trace_id: DSPy::Context.current[:trace_id],
    context_stack_length: DSPy::Context.current[:span_stack].length,
    fiber_id: Fiber.current.object_id
  }
  
  # Call the original method
  original_with_span.call(operation: operation, **attributes, &block)
end

# Create predictor and test
predictor = DSPy::Predict.new(TestSignature)

puts "Starting DSPy::Predict call..."
result = predictor.call(query: "Test query for context propagation")

puts "\n📊 Span creation summary:"
span_calls.each_with_index do |call, index|
  puts "#{index + 1}. #{call[:operation]}"
  puts "   Trace ID: #{call[:context_trace_id]}"
  puts "   Stack length: #{call[:context_stack_length]}" 
  puts "   Fiber ID: #{call[:fiber_id]}"
  puts
end

# Check if spans share the same trace ID (indicating proper nesting)
predict_span = span_calls.find { |s| s[:operation] == "DSPy::Predict.forward" }
llm_span = span_calls.find { |s| s[:operation] == "llm.generate" }

if predict_span && llm_span
  same_trace = predict_span[:context_trace_id] == llm_span[:context_trace_id]
  puts "✅ Context propagation working: #{same_trace}"
  puts "🔍 Predict trace: #{predict_span[:context_trace_id]}"
  puts "🔍 LLM trace: #{llm_span[:context_trace_id]}"
  
  if same_trace
    puts "🎉 SUCCESS: Spans should now be properly nested in Langfuse!"
  else
    puts "❌ FAILED: Spans will still appear as orphaned in Langfuse"
  end
else
  puts "❌ ERROR: Could not find expected spans"
end

puts "\n📄 Response: #{result.response}"

# Flush observability data
DSPy::Observability.flush!