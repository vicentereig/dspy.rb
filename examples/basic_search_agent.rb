#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Basic Search Agent with Structured Outputs
#
# This example demonstrates a ReAct agent that uses tools to search for courses
# and returns structured Course objects (not strings). This showcases DSPy.rb's
# ability to preserve type information through the agent pipeline.
#
# Based on: https://github.com/vicentereig/dspy.rb/issues/133

require 'dotenv'

# Load environment variables from .env file
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

# Define a Course struct to represent course data
class Course < T::Struct
  const :id, Integer
  const :course_title, String
  const :description, String
  const :link, String
end

# Define a toolset with a search_courses tool
class CoursesToolSet < DSPy::Tools::Toolset
  extend T::Sig

  toolset_name "courses_toolset"

  tool :search_courses, description: "Search for and recommend courses related to the query"

  sig { params(query: String).returns(T::Array[Course]) }
  def search_courses(query:)
    puts "🔍 Searching for courses related to: #{query}"

    # Simulate a database search - returns Course objects
    [
      Course.new(
        id: 1,
        course_title: "Introduction to AI",
        description: "Learn the basics of Artificial Intelligence.",
        link: "https://example.com/intro-to-ai"
      ),
      Course.new(
        id: 2,
        course_title: "Advanced Machine Learning",
        description: "Deep dive into machine learning algorithms and techniques.",
        link: "https://example.com/advanced-ml"
      ),
      Course.new(
        id: 3,
        course_title: "Data Science Fundamentals",
        description: "Understand data analysis, visualization, and statistical methods.",
        link: "https://example.com/data-science-fundamentals"
      )
    ]
  end
end

# Define the agent's signature with structured output
class LearningAssistant < DSPy::Signature
  description "You are an AI Learning Assistant specialized in helping users find educational content."

  input do
    const :query, String
  end

  output do
    # Note: output is an Array of Course structs, not a String!
    const :response, T::Array[Course]
  end
end

# Configure DSPy with your LLM provider
DSPy.configure do |config|
  # Basic configuration - works with enhanced prompting (default)
  config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY']
  )

  # Optional: Enable structured outputs for native JSON mode (OpenAI only)
  # This provides more reliable parsing but requires compatible models
  # Uncomment to use:
  # config.lm = DSPy::LM.new(
  #   'openai/gpt-4o-mini',
  #   api_key: ENV['OPENAI_API_KEY'],
  #   structured_outputs: true
  # )

  # Optional: Configure logging
  # config.logger = Dry.Logger(:dspy, formatter: :string) do |log_config|
  #   log_config.add_backend(stream: $stdout)
  # end
end

# Create the agent with tools
toolset = CoursesToolSet.new
agent = DSPy::ReAct.new(
  LearningAssistant,
  tools: toolset.class.to_tools
)

# Run the agent
puts "\n🤖 Starting Learning Assistant Agent"
puts "=" * 60

begin
  result = agent.call(query: "Can you recommend some courses on AI and Machine Learning?")

  puts "\n✅ Agent completed successfully!"
  puts "\n📚 Recommended Courses:"
  puts "-" * 60

  # The response is an Array of Course objects, not a String!
  result.response.each_with_index do |course, index|
    puts "\n#{index + 1}. #{course.course_title}"
    puts "   ID: #{course.id}"
    puts "   Description: #{course.description}"
    puts "   Link: #{course.link}"
  end

  puts "\n" + "=" * 60
  puts "✨ Total courses found: #{result.response.length}"
  puts "🎯 Response type: #{result.response.class.name}"
  puts "📦 First course type: #{result.response.first.class.name}"

rescue DSPy::ReAct::MaxIterationsError => e
  puts "\n❌ Error: Agent reached maximum iterations without completion"
  puts "   #{e.message}"
rescue DSPy::ReAct::TypeMismatchError => e
  puts "\n❌ Error: Type mismatch in response"
  puts "   #{e.message}"
rescue DSPy::ReAct::InvalidActionError => e
  puts "\n❌ Error: Invalid action"
  puts "   #{e.message}"
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.class.name}"
  puts "   #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.first(5).map { |line| "   #{line}" }
end
