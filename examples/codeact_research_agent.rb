#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: CodeAct Research Agent
#
# A lightweight research CLI that uses CodeAct to dynamically generate Ruby code
# for fetching and analyzing web content. The agent writes its own HTTP tools
# on-the-fly rather than relying on predefined toolsets.
#
# WARNING: This executes arbitrary Ruby code via eval. Do not use with untrusted input.
#
# Usage:
#   bundle exec ruby examples/codeact_research_agent.rb
#   bundle exec ruby examples/codeact_research_agent.rb "What is the current Ruby version?"

require 'bundler/setup'
require 'dotenv'

Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'
require 'dspy/code_act'

# Define the research signature
class ResearchQuery < DSPy::Signature
  description "Research a topic by generating Ruby code to fetch and analyze web content."

  input do
    const :query, String, description: "The research question or topic to investigate"
    const :context, String, description: "Available libraries and guidelines for fetching web content"
  end

  output do
    const :answer, String, description: "The comprehensive answer based on research findings"
  end
end

# Configure DSPy
DSPy.configure do |config|
  model = ENV.fetch('CODEACT_MODEL', 'openai/gpt-4o-mini')

  if model.start_with?('anthropic/')
    config.lm = DSPy::LM.new(model, api_key: ENV.fetch('ANTHROPIC_API_KEY'))
  else
    config.lm = DSPy::LM.new(model, api_key: ENV.fetch('OPENAI_API_KEY'))
  end
end

RESEARCH_CONTEXT = <<~CONTEXT
  You are a research agent with access to these Ruby libraries for fetching web content:

  ## Available Libraries (already required)
  - Net::HTTP - for making HTTP requests
  - URI - for parsing URLs
  - JSON - for parsing JSON responses
  - OpenSSL - for HTTPS support

  ## Example: Fetch a webpage
  ```ruby
  uri = URI.parse("https://example.com")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  response = http.get(uri.request_uri)
  body = response.body
  ```

  ## Example: Fetch JSON API
  ```ruby
  uri = URI.parse("https://api.example.com/data")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  response = http.get(uri.request_uri)
  data = JSON.parse(response.body)
  ```

  ## Guidelines
  - Always use `http.use_ssl = true` for https URLs
  - Handle redirects if needed (check response.code)
  - Keep responses concise - extract only relevant information
  - Use `puts` to output findings that should be captured

  ## Useful APIs for research
  - Wikipedia API: https://en.wikipedia.org/api/rest_v1/page/summary/{title}
    - For programming languages, use disambiguation: Ruby_(programming_language), Python_(programming_language)
  - DuckDuckGo Instant Answer: https://api.duckduckgo.com/?q={query}&format=json
    - Returns: AbstractText (summary), RelatedTopics (array of related items)
  - GitHub API: https://api.github.com/repos/{owner}/{repo}
    - Returns: description, stargazers_count, language, etc.
CONTEXT

def run_research(query)
  puts "\n🔬 Research Query: #{query}"
  puts "=" * 60

  agent = DSPy::CodeAct.new(ResearchQuery, max_iterations: 8)

  result = agent.forward(
    query: query,
    context: RESEARCH_CONTEXT
  )

  puts "\n📋 Final Answer:"
  puts "-" * 60
  puts result.answer

  puts "\n🔍 Execution History (#{result.iterations} iterations):"
  puts "-" * 60

  result.history.each do |step|
    puts "\n[Step #{step[:step]}]"
    puts "💭 Thought: #{step[:thought]}"
    puts "💻 Code:"
    step[:ruby_code].to_s.lines.each { |line| puts "   #{line}" }

    if step[:error_message] && !step[:error_message].empty?
      puts "❌ Error: #{step[:error_message]}"
    elsif step[:execution_result]
      output = step[:execution_result].to_s
      if output.length > 500
        puts "✅ Result: #{output[0, 500]}... (truncated)"
      else
        puts "✅ Result: #{output}"
      end
    end
  end

  result
rescue StandardError => e
  puts "\n❌ Error: #{e.class.name}: #{e.message}"
  puts e.backtrace.first(5).map { |l| "   #{l}" }
  nil
end

def interactive_mode
  puts "🤖 CodeAct Research Agent"
  puts "=" * 60
  puts "Enter research queries. The agent will write Ruby code to fetch"
  puts "and analyze web content dynamically."
  puts "Type 'exit' or 'quit' to stop.\n"

  loop do
    print "\n🔎 Query> "
    input = $stdin.gets&.strip

    break if input.nil? || input.empty? || %w[exit quit].include?(input.downcase)

    run_research(input)
  end

  puts "\n👋 Goodbye!"
end

# Main entry point
if ARGV.empty?
  interactive_mode
else
  query = ARGV.join(' ')
  run_research(query)
end
