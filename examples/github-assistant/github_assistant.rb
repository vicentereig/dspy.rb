#!/usr/bin/env ruby
# frozen_string_literal: true

# GitHub Assistant - Example usage of GitHubCLIToolset with DSPy.rb
#
# This script demonstrates how to use the GitHub CLI toolset with a ReAct agent
# to perform various GitHub operations like managing issues, pull requests,
# and repository analysis.
#
# Prerequisites:
# 1. Install and authenticate GitHub CLI: `gh auth login`
# 2. Set up API keys for the LLM provider
# 3. Install dependencies: `bundle install`
#
# Usage:
#   ruby examples/github-assistant/github_assistant.rb

require_relative '../../lib/dspy'
require_relative '../../lib/dspy/tools/github_cli_toolset'
require 'dotenv'
Dotenv.load(File.join(File.dirname(__FILE__), '..', '..', '.env'))

# Signature for the GitHub Assistant
class GitHubAssistant < DSPy::Signature
  description "An intelligent GitHub assistant that can perform repository operations using GitHub CLI"
  
  input do
    const :task, String
    const :repository, String, default: ""
    const :context, String, default: ""
  end
  
  output do
    const :result, String
    const :actions_taken, String, default: ""
  end
end

class GitHubAssistantDemo
  def initialize
    # Configure DSPy with your preferred LM
    # You can use OpenAI, Anthropic, or any other supported provider
    DSPy.configure do |config|
      config.lm = DSPy::LM.new(
        'openai/gpt-4o-mini',  # or 'anthropic/claude-3-haiku-20240307'
        api_key: ENV['OPENAI_API_KEY'] || ENV['ANTHROPIC_API_KEY']
      )
    end
    
    # Set up the GitHub tools
    @github_tools = DSPy::Tools::GitHubCLIToolset.to_tools
    
    # Create the ReAct agent with GitHub tools
    @agent = DSPy::ReAct.new(
      GitHubAssistant,
      tools: @github_tools,
      max_iterations: 15
    )
    
    puts "🚀 GitHub Assistant initialized with #{@github_tools.length} GitHub CLI tools"
    puts "Available tools: #{@github_tools.map(&:name).join(', ')}"
    puts
  end

  def run_demo
    puts "🎯 GitHub Assistant Demo"
    puts "=" * 50
    
    # Demo tasks that showcase different capabilities
    demo_tasks = [
      {
        name: "Repository Analysis",
        task: "Analyze the microsoft/vscode repository: get basic info and list recent open issues",
        repo: "microsoft/vscode"
      },
      {
        name: "Issue Search",
        task: "Find the 5 most recent issues labeled 'bug' and summarize what types of bugs are being reported",
        repo: "rails/rails"
      },
      {
        name: "Pull Request Overview", 
        task: "List open pull requests and identify any that might be ready for review based on their titles",
        repo: "nodejs/node"
      },
      {
        name: "API Exploration",
        task: "Use the GitHub API to get repository statistics (stars, forks, open issues count) and provide a summary",
        repo: "golang/go"
      },
      {
        name: "Multi-Step Analysis",
        task: "Compare the activity between issues and pull requests - which has more recent activity and what does that tell us about the project?",
        repo: "facebook/react"
      }
    ]

    demo_tasks.each_with_index do |demo, index|
      puts "📋 Demo #{index + 1}: #{demo[:name]}"
      puts "Repository: #{demo[:repo]}"
      puts "Task: #{demo[:task]}"
      puts "-" * 50
      
      begin
        # Execute the task with the agent
        response = @agent.call(
          task: demo[:task],
          repository: demo[:repo],
          context: "This is a demo of the GitHub CLI toolset capabilities."
        )
        
        puts "✅ Result:"
        puts response.result
        puts
        
        if response.respond_to?(:actions_taken) && !response.actions_taken.empty?
          puts "🔧 Actions taken:"
          puts response.actions_taken
          puts
        end
        
      rescue => e
        puts "❌ Error executing demo #{index + 1}: #{e.message}"
        puts "This might happen if GitHub CLI is not authenticated or the repository is not accessible."
        puts
      end
      
      puts "=" * 50
      puts
      
      # Add a small delay between demos to avoid rate limiting
      sleep(2) unless index == demo_tasks.length - 1
    end
  end

  def interactive_mode
    puts "🤖 Interactive GitHub Assistant"
    puts "Enter your GitHub-related tasks. Type 'exit' to quit."
    puts "Example: 'List issues from microsoft/vscode labeled as bugs'"
    puts "=" * 50
    
    loop do
      print "You: "
      input = gets.chomp
      
      break if input.downcase == 'exit'
      
      if input.empty?
        puts "Please enter a task or 'exit' to quit."
        next
      end
      
      # Extract repository from input if mentioned
      repo_match = input.match(/(?:from|in|on)\s+([a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+)/)
      repository = repo_match ? repo_match[1] : ""
      
      begin
        puts "🤔 Thinking..."
        
        response = @agent.call(
          task: input,
          repository: repository,
          context: "This is an interactive session. Be helpful and concise."
        )
        
        puts "🤖 Assistant: #{response.result}"
        puts
        
      rescue => e
        puts "❌ Sorry, I encountered an error: #{e.message}"
        puts "Make sure GitHub CLI is authenticated and the repository exists."
        puts
      end
    end
    
    puts "👋 Thanks for using the GitHub Assistant!"
  end
end

# Main execution
if __FILE__ == $0
  # Check if GitHub CLI is available
  unless system('gh --version > /dev/null 2>&1')
    puts "❌ GitHub CLI (gh) is not installed or not in PATH"
    puts "Please install it from: https://cli.github.com/"
    exit 1
  end

  # Check if GitHub CLI is authenticated
  unless system('gh auth status > /dev/null 2>&1')
    puts "❌ GitHub CLI is not authenticated"
    puts "Please run: gh auth login"
    exit 1
  end

  # Check for API keys
  unless ENV['OPENAI_API_KEY'] || ENV['ANTHROPIC_API_KEY']
    puts "❌ No API key found"
    puts "Please set OPENAI_API_KEY or ANTHROPIC_API_KEY environment variable"
    exit 1
  end

  assistant = GitHubAssistantDemo.new
  
  # Check command line arguments
  mode = ARGV[0]
  ARGV.clear # Clear ARGV to prevent gets from reading command line arguments as files
  
  case mode
  when 'demo', nil
    assistant.run_demo
  when 'interactive', 'i'
    assistant.interactive_mode
  else
    puts "Usage:"
    puts "  #{$0}           # Run demo"
    puts "  #{$0} demo      # Run demo" 
    puts "  #{$0} interactive  # Interactive mode"
    exit 1
  end
end