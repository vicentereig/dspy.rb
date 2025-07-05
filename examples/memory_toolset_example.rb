#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dspy'
require 'dspy/tools/memory_toolset'

# Configure DSPy
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    model: 'openai/gpt-4o-mini',
    api_key: ENV.fetch('OPENAI_API_KEY'),
    max_tokens: 1000
  )
end

# Create a signature for Q&A with memory
class MemoryQA < DSPy::Signature
  input :question
  output :answer
end

# Create memory toolset
memory_toolset = DSPy::Tools::MemoryToolset.new

# Convert to individual tools
memory_tools = DSPy::Tools::MemoryToolset.to_tools

puts "Available memory tools:"
memory_tools.each do |tool|
  puts "- #{tool.name}: #{tool.description}"
end
puts

# Create ReAct agent with memory tools
agent = DSPy::ReAct.new(
  signature: MemoryQA,
  tools: memory_tools,
  max_retries: 3
)

# Example interactions
puts "=== Memory-Enabled Agent Demo ==="
puts

# First interaction - store information
question1 = "Please remember that my favorite color is blue and I prefer dark mode for UIs."
puts "User: #{question1}"
response1 = agent.call(question: question1)
puts "Agent: #{response1.answer}"
puts

# Second interaction - retrieve information
question2 = "What UI preferences have I mentioned?"
puts "User: #{question2}"
response2 = agent.call(question: question2)
puts "Agent: #{response2.answer}"
puts

# Third interaction - search memories
question3 = "Search for anything you remember about colors or themes."
puts "User: #{question3}"
response3 = agent.call(question: question3)
puts "Agent: #{response3.answer}"
puts

# Show all stored memories
puts "=== Stored Memories ==="
memory_tools.find { |t| t.name == "memory_list" }.call.each do |key|
  retrieve_tool = memory_tools.find { |t| t.name == "memory_retrieve" }
  value = retrieve_tool.call(key: key)
  puts "- #{key}: #{value}"
end