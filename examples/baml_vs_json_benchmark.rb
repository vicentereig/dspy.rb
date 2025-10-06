#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark'
require 'json'
require 'csv'
require 'dotenv'

# Load environment variables from .env file
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'
require 'sorbet_baml'

# Configure observability
DSPy::Observability.configure!

# Complex agentic signature for benchmarking
class ComplexityLevel < T::Enum
  enums do
    Basic = new('basic')
    Intermediate = new('intermediate')
    Advanced = new('advanced')
  end
end

class TaskDecomposition < DSPy::Signature
  description "Autonomously analyze a research topic and define optimal subtasks with strategic prioritization"

  input do
    const :topic, String, description: "The main research topic to investigate"
    const :context, String, description: "Any additional context or constraints"
    const :complexity_level, ComplexityLevel, description: "Desired complexity level for task decomposition"
  end

  output do
    const :subtasks, T::Array[String], description: "Autonomously defined research subtasks with clear objectives"
    const :task_types, T::Array[String], description: "Type classification for each task (analysis, synthesis, investigation, etc.)"
    const :priority_order, T::Array[Integer], description: "Strategic priority rankings (1-5 scale) for each subtask"
    const :estimated_effort, T::Array[Integer], description: "Effort estimates in hours for each subtask"
    const :dependencies, T::Array[String], description: "Task dependency relationships for optimal sequencing"
    const :agent_requirements, T::Array[String], description: "Suggested agent types/skills needed for each task"
  end
end

class BAMLvsJSONBenchmark
  # Models to test with Enhanced Prompting (January 2025)
  OPENAI_MODELS = %w[
    gpt-4o gpt-4o-mini gpt-5 gpt-5-mini
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
    'gpt-5' => { input: 1.25, output: 10.00 },
    'gpt-5-mini' => { input: 0.25, output: 2.00 },
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
        total_response_time: 0.0,
        total_tokens_saved: 0
      },
      schema_sizes: calculate_schema_sizes
    }

    puts "BAML vs JSON Schema Format Benchmark"
    puts "===================================="
    puts "Comparing JSON Schema vs BAML in Enhanced Prompting Mode"
    puts "Testing #{ALL_MODELS.length} models"
    puts "OpenAI: #{OPENAI_MODELS.length}, Anthropic: #{ANTHROPIC_MODELS.length}, Google: #{GOOGLE_MODELS.length}"
    puts
    puts "Schema Size Comparison:"
    puts "  JSON Schema: #{@results[:schema_sizes][:json_chars]} chars"
    puts "  BAML Schema: #{@results[:schema_sizes][:baml_chars]} chars"
    puts "  Token Savings: #{@results[:schema_sizes][:savings_pct]}%"
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

  def calculate_schema_sizes
    # Get both input and output schemas
    input_json = TaskDecomposition.input_json_schema
    output_json = TaskDecomposition.output_json_schema

    json_input_str = JSON.pretty_generate(input_json)
    json_output_str = JSON.pretty_generate(output_json)
    json_total = json_input_str.length + json_output_str.length

    # For BAML, we'd use the struct classes
    # Note: This is a placeholder until we implement full BAML rendering
    input_baml = TaskDecomposition.input_struct_class.to_baml
    output_baml = TaskDecomposition.output_struct_class.to_baml
    baml_total = input_baml.length + output_baml.length

    savings = ((1 - baml_total.to_f / json_total) * 100).round(1)

    {
      json_chars: json_total,
      baml_chars: baml_total,
      savings_pct: savings,
      json_input: json_input_str,
      json_output: json_output_str,
      baml_input: input_baml,
      baml_output: output_baml
    }
  end

  def test_model(model)
    puts "\nTesting: #{model}"
    puts "-" * 60

    @results[:models][model] = {
      json_format: {},
      baml_format: {}
    }

    # Test both schema formats in Enhanced Prompting mode
    test_format(model, :json_format)
    test_format(model, :baml_format)
  end

  def test_format(model, format_name)
    schema_format = format_name == :json_format ? :json : :baml
    puts "  #{format_name.to_s.gsub('_', ' ').capitalize}..."

    result_key = @results[:models][model][format_name]
    result_key.merge!(
      success: false,
      response_time: 0.0,
      cost: 0.0,
      tokens: { input: 0, output: 0 },
      error: nil
    )

    begin
      # Configure LM with Enhanced Prompting and specified schema format
      lm = create_lm_for_model(model, schema_format: schema_format)
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
        predictor = DSPy::Predict.new(TaskDecomposition)

        # Verify the predictor is using the correct schema format
        unless predictor.prompt.schema_format == schema_format
          raise "Predictor schema_format mismatch: expected #{schema_format}, got #{predictor.prompt.schema_format}"
        end

        result = predictor.call(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories",
          complexity_level: ComplexityLevel::Intermediate
        )

        # Validate result structure
        validate_result(result)
      end

      # Unsubscribe from event
      DSPy.events.unsubscribe(subscription)

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

      # Calculate token savings if using BAML
      if schema_format == :baml
        # Approximate input token savings based on schema size difference
        schema_savings = @results[:schema_sizes][:json_chars] - @results[:schema_sizes][:baml_chars]
        # Rough estimate: 1 token ≈ 4 chars
        estimated_tokens_saved = schema_savings / 4
        @results[:summary][:total_tokens_saved] += estimated_tokens_saved
      end

      result_key.merge!(
        success: true,
        response_time: response_time,
        cost: cost,
        tokens: { input: input_tokens, output: output_tokens }
      )

      @results[:summary][:successful_tests] += 1
      @results[:summary][:total_cost] += cost
      @results[:summary][:total_response_time] += response_time

      puts "    ✅ Success (#{(response_time * 1000).round(0)}ms, $#{cost.round(6)}, #{input_tokens}→#{output_tokens} tokens)"

    rescue => e
      result_key[:error] = e.message
      @results[:summary][:failed_tests] += 1
      puts "    ❌ Failed: #{e.message}"
    ensure
      @results[:summary][:total_tests] += 1
    end
  end

  def create_lm_for_model(model, schema_format: :json)
    # Always use Enhanced Prompting (structured_outputs: false) for this benchmark
    case model
    when /^gpt-/
      DSPy::LM.new(
        "openai/#{model}",
        api_key: ENV['OPENAI_API_KEY'],
        structured_outputs: false,  # Force Enhanced Prompting
        schema_format: schema_format
      )
    when /^claude-/
      DSPy::LM.new(
        "anthropic/#{model}",
        api_key: ENV['ANTHROPIC_API_KEY'],
        structured_outputs: false,  # Force Enhanced Prompting
        schema_format: schema_format
      )
    when /^gemini-/
      DSPy::LM.new(
        "gemini/#{model}",
        api_key: ENV['GEMINI_API_KEY'],
        structured_outputs: false,  # Force Enhanced Prompting
        schema_format: schema_format
      )
    else
      raise ArgumentError, "Unknown model provider: #{model}"
    end
  end

  def validate_result(result)
    raise "Missing subtasks" unless result.subtasks
    raise "Subtasks not an array" unless result.subtasks.is_a?(Array)
    raise "Missing task_types" unless result.task_types
    raise "Missing priority_order" unless result.priority_order
    raise "Missing estimated_effort" unless result.estimated_effort
    raise "Missing dependencies" unless result.dependencies
    raise "Missing agent_requirements" unless result.agent_requirements
  end

  def print_summary(duration)
    puts "\n" + "="*80
    puts "BENCHMARK RESULTS"
    puts "="*80

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

    if summary[:total_tokens_saved] > 0
      puts "\n💰 Token Savings (BAML vs JSON):"
      puts "  Total tokens saved: ~#{summary[:total_tokens_saved]}"
      puts "  Schema size reduction: #{@results[:schema_sizes][:savings_pct]}%"
    end

    puts "\nPer-Model Comparison:"
    puts "  #{'Model'.ljust(30)} #{'Format'.ljust(15)} #{'Status'.ljust(8)} #{'Time'.ljust(10)} #{'Cost'.ljust(12)} #{'Tokens'}"
    puts "  " + "-" * 95

    @results[:models].each do |model, formats|
      formats.each do |format_name, data|
        status = data[:success] ? "✅" : "❌"
        time = data[:success] ? "#{(data[:response_time] * 1000).round(0)}ms" : "N/A"
        cost = data[:success] ? "$#{data[:cost].round(6)}" : "N/A"
        tokens = data[:success] ? "#{data[:tokens][:input]}→#{data[:tokens][:output]}" : "N/A"
        format_display = format_name.to_s.gsub('_format', '').upcase

        puts "  #{model.ljust(30)} #{format_display.ljust(15)} #{status.ljust(8)} #{time.ljust(10)} #{cost.ljust(12)} #{tokens}"

        # Print error if failed
        if !data[:success] && data[:error]
          puts "     └─ Error: #{data[:error]}"
        end
      end
    end

    puts
  end

  def export_results
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")

    # Export JSON
    json_filename = "baml_benchmark_#{timestamp}.json"
    File.write(json_filename, JSON.pretty_generate(@results))
    puts "📊 JSON results exported to: #{json_filename}"

    # Export CSV
    csv_filename = "baml_benchmark_#{timestamp}.csv"
    CSV.open(csv_filename, 'w') do |csv|
      # Header
      csv << ['Model', 'Format', 'Success', 'Response Time (ms)', 'Cost ($)', 'Input Tokens', 'Output Tokens', 'Total Tokens', 'Error']

      # Data rows
      @results[:models].each do |model, formats|
        formats.each do |format_name, data|
          csv << [
            model,
            format_name.to_s.gsub('_format', '').upcase,
            data[:success] ? 'Yes' : 'No',
            data[:success] ? (data[:response_time] * 1000).round(0) : 'N/A',
            data[:success] ? data[:cost].round(6) : 'N/A',
            data[:success] ? data[:tokens][:input] : 'N/A',
            data[:success] ? data[:tokens][:output] : 'N/A',
            data[:success] ? (data[:tokens][:input] + data[:tokens][:output]) : 'N/A',
            data[:error] || ''
          ]
        end
      end
    end
    puts "📊 CSV results exported to: #{csv_filename}"

    # Export schema comparison
    schema_filename = "schema_comparison_#{timestamp}.txt"
    File.write(schema_filename, <<~COMPARISON)
      Schema Format Comparison
      ========================

      JSON Schema (Input + Output): #{@results[:schema_sizes][:json_chars]} chars
      BAML Schema (Input + Output): #{@results[:schema_sizes][:baml_chars]} chars
      Token Savings: #{@results[:schema_sizes][:savings_pct]}%

      JSON Input Schema:
      #{@results[:schema_sizes][:json_input]}

      JSON Output Schema:
      #{@results[:schema_sizes][:json_output]}

      BAML Input Schema:
      #{@results[:schema_sizes][:baml_input]}

      BAML Output Schema:
      #{@results[:schema_sizes][:baml_output]}
    COMPARISON
    puts "📊 Schema comparison exported to: #{schema_filename}"
  end
end

# Run benchmark if executed directly
if __FILE__ == $0
  benchmark = BAMLvsJSONBenchmark.new
  benchmark.run_benchmark
end
