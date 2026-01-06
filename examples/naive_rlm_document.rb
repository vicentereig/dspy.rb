#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Naive RLM Document Navigation
#
# Demonstrates the Naive RLM pattern for navigating large documents
# without loading them entirely into the LLM context window.
#
# The LLM outputs structured actions (peek, grep, partition, finish)
# instead of generating code like the original RLM approach.
#
# See ADR-017 for design rationale.
#
# Usage:
#   # With a text file:
#   bundle exec ruby examples/naive_rlm_document.rb --file path/to/document.txt \
#     --query "What are the key findings?"
#
#   # With a PDF (requires pdf-reader gem):
#   bundle exec ruby examples/naive_rlm_document.rb --file path/to/paper.pdf \
#     --query "What methodology was used?"
#
#   # With verbose output to see action trace:
#   bundle exec ruby examples/naive_rlm_document.rb --file doc.txt \
#     --query "Summarize the results" --verbose

require 'optparse'
require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

# Configure observability
DSPy::Observability.configure!

DEFAULT_MODEL = ENV.fetch('DSPY_MODEL', 'openai/gpt-4o-mini')
DEFAULT_MAX_ITERATIONS = 10

options = {
  file_path: nil,
  query: nil,
  model: DEFAULT_MODEL,
  max_iterations: DEFAULT_MAX_ITERATIONS,
  verbose: false
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: bundle exec ruby examples/naive_rlm_document.rb --file PATH --query QUERY [options]'

  opts.on('--file PATH', 'Path to document (text or PDF)') { |v| options[:file_path] = v }
  opts.on('--query QUERY', 'Question to answer about the document') { |v| options[:query] = v }
  opts.on('--model MODEL', "Model ID (default: #{DEFAULT_MODEL})") { |v| options[:model] = v }
  opts.on('--max-iterations N', Integer, "Max navigation iterations (default: #{DEFAULT_MAX_ITERATIONS})") { |v| options[:max_iterations] = v }
  opts.on('--verbose', 'Show action trace during navigation') { options[:verbose] = true }
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit 0
  end
end

parser.parse!(ARGV)

# Handle positional arguments
options[:file_path] ||= ARGV.shift
options[:query] ||= ARGV.shift

unless options[:file_path] && options[:query]
  warn 'Both --file and --query are required.'
  puts parser
  exit 1
end

unless File.exist?(options[:file_path])
  warn "File not found: #{options[:file_path]}"
  exit 1
end

# Check for required API key
provider = options[:model].to_s.split('/', 2).first
required_key = case provider
               when 'openai' then 'OPENAI_API_KEY'
               when 'anthropic' then 'ANTHROPIC_API_KEY'
               when 'gemini', 'google' then 'GEMINI_API_KEY'
               end

if required_key && ENV[required_key].to_s.strip.empty?
  warn "Missing #{required_key}. Set it in .env or your shell."
  exit 1
end

# Configure DSPy
DSPy.configure do |config|
  api_key = required_key ? ENV[required_key] : nil
  config.lm = DSPy::LM.new(options[:model], api_key: api_key)
end

# Extract lines from file
def extract_lines(file_path)
  if file_path.end_with?('.pdf')
    begin
      require 'pdf/reader'
      reader = PDF::Reader.new(file_path)
      reader.pages.flat_map { |page| page.text.lines.map(&:chomp) }
    rescue LoadError
      warn "PDF support requires pdf-reader gem. Install with: gem install pdf-reader"
      exit 1
    end
  else
    File.readlines(file_path).map(&:chomp)
  end
end

puts "Reading: #{options[:file_path]}"
lines = extract_lines(options[:file_path])

if lines.empty? || lines.all?(&:empty?)
  warn 'No content extracted from file.'
  exit 1
end

puts "Extracted #{lines.length} lines"
puts "Query: #{options[:query]}"
puts

# Create navigator and run
navigator = DSPy::NaiveRLM::Navigator.new(max_iterations: options[:max_iterations])

# Hook into events for verbose output
if options[:verbose]
  DSPy.events.subscribe('lm.request') do |_event, attrs|
    puts "[LM] Calling model..."
  end

  DSPy.events.subscribe('lm.response') do |_event, attrs|
    if attrs['lm.input_tokens'] && attrs['lm.output_tokens']
      puts "[LM] Tokens: #{attrs['lm.input_tokens']} in / #{attrs['lm.output_tokens']} out"
    end
  end
end

puts "Navigating document..."
puts

start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = navigator.forward(lines: lines, query: options[:query])
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

# Display results
puts "=== Answer ==="
puts result.answer
puts

puts "=== Statistics ==="
puts "Iterations: #{result.iterations}"
puts "Time: #{elapsed.round(2)}s"

if result.max_iterations_reached
  puts "Note: Max iterations (#{options[:max_iterations]}) reached"
end

if options[:verbose] && result.history.any?
  puts
  puts "=== Action History ==="
  result.history.each_with_index do |entry, i|
    puts "#{i + 1}. #{entry[0, 200]}#{'...' if entry.length > 200}"
  end
end

# Flush observability
DSPy::Observability.flush! if DSPy::Observability.respond_to?(:flush!)

puts
puts "Done."
