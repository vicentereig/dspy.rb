#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative 'lib/dspy'

# Configure observability
DSPy::Observability.configure!

puts "🔍 Testing OpenTelemetry context propagation..."

# Test 1: Basic nested spans
puts "\n=== Test 1: Basic nested DSPy::Context spans ==="
DSPy::Context.with_span(operation: 'outer') do |outer_span|
  puts "🟢 Inside outer span - ID: #{outer_span&.context&.trace_id}"
  
  DSPy::Context.with_span(operation: 'inner') do |inner_span|
    puts "🔵 Inside inner span - ID: #{inner_span&.context&.trace_id}"
    puts "🔍 Same trace ID? #{outer_span&.context&.trace_id == inner_span&.context&.trace_id}"
  end
end

# Test 2: Check if context is properly inherited across method calls
puts "\n=== Test 2: Method call context propagation ==="

def call_with_span
  DSPy::Context.with_span(operation: 'method_span') do |span|
    puts "🟡 Inside method span - ID: #{span&.context&.trace_id}"
    return span&.context&.trace_id
  end
end

DSPy::Context.with_span(operation: 'main_span') do |main_span|
  puts "🟢 Main span - ID: #{main_span&.context&.trace_id}"
  method_trace_id = call_with_span
  puts "🔍 Method trace ID matches main? #{main_span&.context&.trace_id == method_trace_id}"
end

# Test 3: Simulate the exact DSPy::Predict -> LM call pattern
puts "\n=== Test 3: Simulated DSPy::Predict -> LM pattern ==="

def simulate_lm_instrument_request
  DSPy::Context.with_span(operation: 'llm.generate') do |llm_span|
    puts "🔴 LM span - ID: #{llm_span&.context&.trace_id}"
    return llm_span&.context&.trace_id
  end
end

def simulate_predict_forward
  DSPy::Context.with_span(operation: 'DSPy::Predict.forward') do |predict_span|
    puts "🟢 Predict span - ID: #{predict_span&.context&.trace_id}"
    
    # This simulates the `current_lm.chat(self, input_values)` call
    lm_trace_id = simulate_lm_instrument_request
    
    puts "🔍 LM trace ID matches predict? #{predict_span&.context&.trace_id == lm_trace_id}"
    return predict_span&.context&.trace_id == lm_trace_id
  end
end

nested_properly = simulate_predict_forward
puts "✅ Context propagation working: #{nested_properly}"

# Test 4: Check Thread vs Fiber context
puts "\n=== Test 4: Thread vs Fiber context ==="
puts "🧵 Current thread ID: #{Thread.current.object_id}"
puts "🔄 Current fiber ID: #{Fiber.current.object_id}"

# Test fiber context 
context = DSPy::Context.current
puts "📦 DSPy context trace_id: #{context[:trace_id]}"
puts "📚 DSPy span stack length: #{context[:span_stack].length}"

# Flush and finish
DSPy::Observability.flush!

puts "\n🎯 If context propagation is broken, traces will appear as separate root spans in Langfuse"
puts "🎯 If working properly, inner spans should be nested under outer spans"