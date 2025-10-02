#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark'
require 'json'
require 'csv'
require 'dotenv'

# Load environment variables from .env file
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

# Configure observability
DSPy::Observability.configure!

# Simple test signature for benchmarking
class ActionType < T::Enum
  enums do
    Create = new('create')
    Update = new('update')
    Delete = new('delete')
  end
end

class TodoAction < T::Struct
  const :action_type, ActionType
  const :task, String
  const :priority, String, default: 'medium'
end

class TodoListManagementSignature < DSPy::Signature
  description "Parse user request into structured todo actions"

  input do
    const :user_request, String, description: "Natural language request about todos"
  end

  output do
    const :actions, T::Array[TodoAction], description: "Actions to execute"
    const :summary, String, description: "Brief summary of what will be done"
  end
end

class JSONModesBenchmark
  # Model constants for testing native structured outputs (January 2025)
  OPENAI_MODELS = %w[
    gpt-4o gpt-4o-mini
  ].freeze

  ANTHROPIC_MODELS = %w[
    claude-sonnet-4-5-20250929
    claude-opus-4-1-20250805
  ].freeze

  GOOGLE_MODELS = %w[
    gemini-2.5-pro
    gemini-2.5-flash
  ].freeze

  ALL_MODELS = (OPENAI_MODELS + ANTHROPIC_MODELS + GOOGLE_MODELS).freeze

  # Model pricing per 1M tokens (input/output) - January 2025
  MODEL_PRICING = {
    'gpt-4o' => { input: 2.50, output: 10.00 },
    'gpt-4o-mini' => { input: 0.15, output: 0.60 },
    'claude-sonnet-4-5-20250929' => { input: 3.00, output: 15.00 },
    'claude-opus-4-1-20250805' => { input: 15.00, output: 75.00 },
    'gemini-2.5-pro' => { input: 1.25, output: 5.00 },
    'gemini-2.5-flash' => { input: 0.075, output: 0.30 }
  }.freeze

  def initialize
    @results = {
      models: {},
      summary: {
        total_tests: 0,
        successful_tests: 0,
        failed_tests: 0,
        total_cost: 0.0,
        total_response_time: 0.0
      }
    }

    puts "Native Structured Outputs Benchmark"
    puts "===================================="
    puts "Testing #{ALL_MODELS.length} models with native structured outputs"
    puts "OpenAI: #{OPENAI_MODELS.length}, Anthropic: #{ANTHROPIC_MODELS.length}, Google: #{GOOGLE_MODELS.length}"
    puts
  end

  def run_benchmark
    puts "🚀 Starting benchmark..."
    puts

    start_time = Time.now

    ALL_MODELS.each do |model|
      test_model(model)
    end

    end_time = Time.now
    total_duration = end_time - start_time

    print_summary(total_duration)
    export_results
  end

  private

  def test_model(model)
    puts "\nTesting: #{model}"
    puts "-" * 60

    @results[:models][model] = {
      success: false,
      response_time: 0.0,
      cost: 0.0,
      tokens: { input: 0, output: 0 },
      error: nil
    }

    begin
      # Configure LM with structured outputs enabled
      lm = create_lm_for_model(model)
      DSPy.configure { |config| config.lm = lm }

      # Track usage with event subscription
      captured_usage = nil
      subscription = DSPy.events.subscribe('lm.tokens') do |_, attrs|
        captured_usage = {
          input: attrs[:input_tokens],
          output: attrs[:output_tokens],
          total: attrs[:total_tokens]
        }
      end

      # Run test and capture result
      result = nil
      response_time = Benchmark.realtime do
        predictor = DSPy::Predict.new(TodoListManagementSignature)
        result = predictor.call(
          user_request: "Add task to buy groceries, mark urgent task as complete, and schedule team meeting for Friday at 2pm"
        )

        # Validate result structure
        validate_result(result)
      end

      # Unsubscribe from event
      DSPy.events.unsubscribe('lm.tokens', subscription)

      # Get usage from captured event
      input_tokens = captured_usage&.dig(:input) || 0
      output_tokens = captured_usage&.dig(:output) || 0

      # Calculate cost
      pricing = MODEL_PRICING[model]
      cost = if pricing
        (input_tokens * pricing[:input] / 1_000_000.0) +
        (output_tokens * pricing[:output] / 1_000_000.0)
      else
        0.0
      end

      @results[:models][model].merge!(
        success: true,
        response_time: response_time,
        cost: cost,
        tokens: { input: input_tokens, output: output_tokens }
      )

      @results[:summary][:successful_tests] += 1
      @results[:summary][:total_cost] += cost
      @results[:summary][:total_response_time] += response_time

      puts "✅ Success (#{(response_time * 1000).round(0)}ms, $#{cost.round(6)})"

    rescue => e
      @results[:models][model][:error] = e.message
      @results[:summary][:failed_tests] += 1
      puts "❌ Failed: #{e.message}"
    ensure
      @results[:summary][:total_tests] += 1
    end
  end

  def create_lm_for_model(model)
    case model
    when /^gpt-/
      DSPy::LM.new(
        "openai/#{model}",
        api_key: ENV['OPENAI_API_KEY'],
        structured_outputs: true
      )
    when /^claude-/
      DSPy::LM.new(
        "anthropic/#{model}",
        api_key: ENV['ANTHROPIC_API_KEY'],
        structured_outputs: true
      )
    when /^gemini-/
      DSPy::LM.new(
        "gemini/#{model}",
        api_key: ENV['GEMINI_API_KEY'],
        structured_outputs: true
      )
    else
      raise ArgumentError, "Unknown model provider: #{model}"
    end
  end

  def validate_result(result)
    raise "Missing actions" unless result.actions
    raise "Actions not an array" unless result.actions.is_a?(Array)
    raise "Invalid action types" unless result.actions.all? { |a| a.is_a?(T::Struct) }
  end

  def print_summary(duration)
    puts "\n" + "="*60
    puts "BENCHMARK RESULTS"
    puts "="*60

    summary = @results[:summary]
    success_rate = summary[:total_tests] > 0 ?
      (summary[:successful_tests].to_f / summary[:total_tests] * 100).round(1) : 0
    avg_time = summary[:successful_tests] > 0 ?
      (summary[:total_response_time] / summary[:successful_tests]).round(3) : 0

    puts "\nOverall Statistics:"
    puts "  Total tests: #{summary[:total_tests]}"
    puts "  Successful: #{summary[:successful_tests]}"
    puts "  Failed: #{summary[:failed_tests]}"
    puts "  Success rate: #{success_rate}%"
    puts "  Average response time: #{avg_time}s"
    puts "  Total cost: $#{summary[:total_cost].round(4)}"
    puts "  Total duration: #{duration.round(1)}s"

    puts "\nPer-Model Results:"
    puts "  #{'Model'.ljust(35)} #{'Status'.ljust(10)} #{'Time'.ljust(10)} #{'Cost'.ljust(12)} #{'Tokens'}"
    puts "  " + "-" * 85

    @results[:models].each do |model, data|
      status = data[:success] ? "✅" : "❌"
      time = data[:success] ? "#{(data[:response_time] * 1000).round(0)}ms" : "N/A"
      cost = data[:success] ? "$#{data[:cost].round(6)}" : "N/A"
      tokens = data[:success] ? "#{data[:tokens][:input]}→#{data[:tokens][:output]}" : "N/A"

      puts "  #{model.ljust(35)} #{status.ljust(10)} #{time.ljust(10)} #{cost.ljust(12)} #{tokens}"
    end

    puts
  end

  def export_results
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    filename = "benchmark_results_#{timestamp}.json"

    File.write(filename, JSON.pretty_generate(@results))
    puts "📊 Results exported to: #{filename}"
  end
end

# Run benchmark if executed directly
if __FILE__ == $0
  benchmark = JSONModesBenchmark.new
  benchmark.run_benchmark
end
