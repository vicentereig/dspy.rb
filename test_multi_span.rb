#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require_relative 'lib/dspy'
require 'logger'

# Enable debug logging
logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

puts "=== Multi-Span Langfuse Export Test ==="

# Check environment variables
puts "LANGFUSE_PUBLIC_KEY: #{ENV['LANGFUSE_PUBLIC_KEY'] ? "Set (#{ENV['LANGFUSE_PUBLIC_KEY'][0..10]}...)" : 'Not set'}"
puts "LANGFUSE_SECRET_KEY: #{ENV['LANGFUSE_SECRET_KEY'] ? "Set (#{ENV['LANGFUSE_SECRET_KEY'][0..10]}...)" : 'Not set'}"

# Configure DSPy observability
DSPy::Observability.configure!
puts "Observability enabled: #{DSPy::Observability.enabled?}"

unless DSPy::Observability.enabled?
  puts "Observability not enabled - exiting"
  exit 1
end

puts "\n=== Creating Multiple Spans ==="

# Test 1: Multiple sequential spans
puts "Creating 10 sequential spans..."
10.times do |i|
  DSPy::Context.with_span(
    operation: "test.sequential_span_#{i}",
    span_index: i,
    test_type: "sequential"
  ) do |span|
    puts "  - Span #{i}: #{span.class}" if span
    sleep(0.02)
  end
end

puts "\n=== Creating Nested Spans ==="

# Test 2: Nested spans
DSPy::Context.with_span(
  operation: "test.parent_operation",
  test_type: "nested_parent"
) do |parent_span|
  puts "Parent span: #{parent_span.class}" if parent_span
  
  5.times do |i|
    DSPy::Context.with_span(
      operation: "test.child_operation_#{i}",
      child_index: i,
      test_type: "nested_child"
    ) do |child_span|
      puts "  Child #{i}: #{child_span.class}" if child_span
      sleep(0.01)
    end
  end
end

puts "\n=== Creating Rapid Spans (Batch Test) ==="

# Test 3: Rapid span creation to test batching
20.times do |i|
  DSPy::Context.with_span(
    operation: "test.batch_span_#{i}",
    batch_index: i,
    test_type: "rapid_batch"
  ) do |span|
    # Minimal work to test batching
  end
end

puts "\n=== Forcing Export ==="
DSPy::Observability.flush!
puts "Force flush completed"

puts "\n=== Waiting for Async Export (15 seconds) ==="
sleep(15)

puts "\n=== Test Summary ==="
puts "✅ Created 10 sequential spans"
puts "✅ Created 1 parent + 5 child spans (6 total)"
puts "✅ Created 20 rapid batch spans"
puts "📊 Total spans created: 36"
puts ""
puts "Check your Langfuse dashboard for these traces:"
puts "- test.sequential_span_* (10 traces)"
puts "- test.parent_operation (1 trace with 5 child spans)"
puts "- test.batch_span_* (20 traces)"

puts "\n=== Development Log Check ==="
puts "Recent observability logs:"
system("tail -50 log/development.log | grep 'observability\\.' | tail -10") if File.exist?('log/development.log')