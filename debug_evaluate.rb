#!/usr/bin/env ruby

require_relative 'lib/dspy'
require 'ostruct'

# Mock program for testing
class MockMathProgram
  attr_accessor :responses

  def initialize
    @responses = {
      "2 + 3" => "5",
      "10 - 4" => "6", 
    }
  end

  def call(problem:)
    puts "MockMathProgram.call received problem: #{problem.inspect} (#{problem.class})"
    answer = @responses[problem] || "unknown"
    puts "MockMathProgram.call returning answer: #{answer.inspect}"
    # Simulate a struct-like response
    result = OpenStruct.new(problem: problem, answer: answer)
    puts "MockMathProgram.call returning: #{result.inspect}"
    result
  end
end

# Simple exact match metric
metric = proc do |example, prediction|
  puts "Metric received example: #{example.inspect}"
  puts "Metric received prediction: #{prediction.inspect}"
  
  expected = case example
             when Hash
               example.dig(:expected, :answer) || example.dig('expected', 'answer')
             else
               example.expected_values[:answer] rescue nil
             end
  
  puts "Expected: #{expected.inspect}, Got: #{prediction.answer.inspect}"
  expected == prediction.answer
end

# Test data
example = { input: { problem: "2 + 3" }, expected: { answer: "5" } }

# Create evaluator
mock_program = MockMathProgram.new
evaluator = DSPy::Evaluate.new(mock_program, metric: metric)

puts "=== Debug Evaluation ==="
puts "Example: #{example.inspect}"

begin
  result = evaluator.call(example)
  puts "Result: #{result.inspect}"
  puts "Passed: #{result.passed}"
  puts "Prediction: #{result.prediction.inspect}"
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end