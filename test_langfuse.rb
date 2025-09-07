#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/dspy'
require 'logger'

# Enable debug logging
logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

# Check environment variables
puts "=== Checking Langfuse Environment Variables ==="
puts "LANGFUSE_PUBLIC_KEY: #{ENV['LANGFUSE_PUBLIC_KEY'] ? 'Set' : 'Not set'}"
puts "LANGFUSE_SECRET_KEY: #{ENV['LANGFUSE_SECRET_KEY'] ? 'Set' : 'Not set'}"
puts "LANGFUSE_HOST: #{ENV['LANGFUSE_HOST'] || 'Not set (will use cloud.langfuse.com)'}"
puts

# Configure DSPy observability
puts "=== Configuring Observability ==="
DSPy::Observability.configure!
puts "Observability enabled: #{DSPy::Observability.enabled?}"
puts "Endpoint: #{DSPy::Observability.endpoint}"
puts

# Check if tracer is available
puts "=== Checking Tracer ==="
tracer = DSPy::Observability.tracer
puts "Tracer available: #{!tracer.nil?}"
puts "Tracer class: #{tracer.class}" if tracer
puts

# Try to create a span using Context
puts "=== Creating Test Span via Context ==="
result = DSPy::Context.with_span(operation: 'test.manual_span', test_attribute: 'test_value') do |span|
  puts "Inside span block"
  puts "Span object: #{span.inspect}"
  
  # Simulate some work
  sleep 0.1
  
  "Test result"
end
puts "Span result: #{result}"
puts

# Force flush to ensure spans are exported
puts "=== Forcing Flush ==="
DSPy::Observability.flush!
puts "Flush completed"
puts

# Check OpenTelemetry tracer provider
puts "=== OpenTelemetry Details ==="
provider = OpenTelemetry.tracer_provider
puts "Tracer provider class: #{provider.class}"

# Check span processors
if provider.respond_to?(:span_processors)
  puts "Span processors:"
  provider.span_processors.each_with_index do |processor, i|
    puts "  #{i}: #{processor.class}"
    if processor.is_a?(DSPy::Observability::AsyncSpanProcessor)
      puts "     - AsyncSpanProcessor detected"
    end
  end
end

# Wait a bit for async export
puts
puts "=== Waiting for async export (5 seconds) ==="
sleep 5

puts
puts "=== Test Complete ==="
puts "Check your Langfuse dashboard for the trace named 'test.manual_span'"