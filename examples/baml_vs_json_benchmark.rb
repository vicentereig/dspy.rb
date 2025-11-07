#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark'
require 'json'
require 'csv'
require 'dotenv'
require 'fileutils'

require 'sorbet/toon'

# Load environment variables from .env file
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'
require 'sorbet_baml'

# Ensure logger directory exists for local runs
FileUtils.mkdir_p(File.expand_path('../log', __dir__)) unless File.exist?(File.expand_path('../log', __dir__))

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

class TaskType < T::Enum
  enums do
    Analysis = new('analysis')
    Synthesis = new('synthesis')
    Investigation = new('investigation')
    Planning = new('planning')
    Delivery = new('delivery')
  end
end

class Task < T::Struct
  const :name, String
  const :objective, String
  const :success_metric, String
end

class EstimatedEffortWithReasoning < T::Struct
  const :hours, Integer
  const :rationale, String
end

class TaskDecomposition < DSPy::Signature
  description "Autonomously analyze a research topic and define optimal subtasks with strategic prioritization"

  input do
    const :topic, String, description: "The main research topic to investigate"
    const :context, String, description: "Any additional context or constraints"
    const :complexity_level, ComplexityLevel, description: "Desired complexity level for task decomposition"
  end

  output do
    const :subtasks, T::Array[Task], description: "Autonomously defined research tasks with objectives and success metrics"
    const :task_types, T::Array[TaskType], description: "Type classification for each task (analysis, synthesis, investigation, etc.)"
    const :priority_order, T::Array[Integer], description: "Strategic priority rankings (1-5 scale) for each subtask"
    const :estimated_effort, T::Array[EstimatedEffortWithReasoning], description: "Effort estimates in hours with supporting rationale"
    const :dependencies, T::Array[Task], description: "Task dependency relationships captured as structured tasks"
    const :agent_requirements, T::Array[String], description: "Suggested agent types/skills needed for each task"
  end
end

SCHEMA_OPTIONS = [
  { key: :json_schema, label: 'JSON Schema', format: :json },
  { key: :baml_schema, label: 'BAML Schema', format: :baml }
].freeze

DATA_OPTIONS = [
  { key: :json_data, label: 'JSON Data', format: :json },
  { key: :toon_data, label: 'TOON Data', format: :toon }
].freeze

FORMAT_COMBINATIONS = SCHEMA_OPTIONS.flat_map do |schema|
  DATA_OPTIONS.map do |data|
    {
      key: "#{schema[:key]}__#{data[:key]}",
      schema_key: schema[:key],
      data_key: data[:key],
      schema_label: schema[:label],
      data_label: data[:label],
      schema_format: schema[:format],
      data_format: data[:format]
    }
  end
end.freeze

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
    @live_run = ENV['BAML_BENCHMARK_LIVE'] != '0'
    @models_to_test = gather_models
    if @models_to_test.empty?
      warn "⚠️  No provider API keys detected. Falling back to prompt analysis mode."
      @live_run = false
    end

    @results = {
      mode: @live_run ? 'lm' : 'prompt_analysis',
      prompt_combinations: FORMAT_COMBINATIONS,
      models: {},
      summary: {
        total_tests: 0,
        successful_tests: 0,
        failed_tests: 0,
        total_cost: 0.0,
        total_response_time: 0.0,
        schema_token_savings: 0,
        data_token_savings: 0
      },
      schema_sizes: calculate_schema_sizes,
      data_sizes: calculate_data_sizes
    }

    puts "BAML vs JSON Schema Format Benchmark"
    puts "===================================="
    puts "Comparing Schema Formats (JSON vs BAML) and Data Formats (JSON vs TOON)"
    puts "Mode: #{@live_run ? 'Live LM Run' : 'Prompt Analysis'}"
    puts "Testing #{@models_to_test.length} models"
    puts "  OpenAI: #{OPENAI_MODELS.length} (#{ENV['OPENAI_API_KEY'] ? 'enabled' : 'missing key'})"
    puts "  Anthropic: #{ANTHROPIC_MODELS.length} (#{ENV['ANTHROPIC_API_KEY'] ? 'enabled' : 'missing key'})"
    puts "  Google: #{GOOGLE_MODELS.length} (#{ENV['GEMINI_API_KEY'] ? 'enabled' : 'missing key'})"
    puts
    puts "Schema Size Comparison:"
    puts "  JSON Schema: #{@results[:schema_sizes][:json_chars]} chars"
    puts "  BAML Schema: #{@results[:schema_sizes][:baml_chars]} chars"
    puts "  Token Savings: #{@results[:schema_sizes][:savings_pct]}%"
    puts
    puts "Data Payload Comparison (single request):"
    puts "  JSON Data: #{@results[:data_sizes][:json_chars]} chars"
    puts "  TOON Data: #{@results[:data_sizes][:toon_chars]} chars"
    puts "  Token Savings: #{@results[:data_sizes][:savings_pct]}%"
    puts
  end

  def run_benchmark
    if @live_run
      run_live_benchmark
    else
      run_prompt_analysis
    end
  end

  def run_live_benchmark
    puts "🚀 Starting live benchmark..."
    puts

    start_time = Time.now

    @models_to_test.each do |model|
      test_model(model)
    end

    end_time = Time.now
    total_duration = end_time - start_time

    print_summary(total_duration)
    export_results
  end

  def run_prompt_analysis
    puts "🧪 Starting prompt analysis (no external API calls)..."
    puts

    input_values = benchmark_input_values

    @results[:prompt_analysis] = FORMAT_COMBINATIONS.map do |combo|
      prompt = DSPy::Prompt.from_signature(
        TaskDecomposition,
        schema_format: combo[:schema_format],
        data_format: combo[:data_format]
      )

      system_prompt = prompt.render_system_prompt
      user_prompt = prompt.render_user_prompt(input_values)
      total_chars = system_prompt.length + user_prompt.length

      {
        key: combo[:key],
        schema_format: combo[:schema_format],
        data_format: combo[:data_format],
        schema_label: combo[:schema_label],
        data_label: combo[:data_label],
        system_chars: system_prompt.length,
        user_chars: user_prompt.length,
        total_chars: total_chars,
        estimated_tokens: (total_chars / 4.0).round
      }
    end

    export_prompt_analysis_results
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

  def calculate_data_sizes
    input_struct = TaskDecomposition.input_struct_class.new(**benchmark_input_values)
    output_values = sample_output_values
    output_struct = TaskDecomposition.output_struct_class.new(**output_values)

    json_input = JSON.pretty_generate(DSPy::TypeSerializer.serialize(input_struct))
    json_output = JSON.pretty_generate(DSPy::TypeSerializer.serialize(output_struct))
    json_payload = "#{json_input}\n\n#{json_output}"

    toon_input = Sorbet::Toon.encode(
      benchmark_input_values,
      signature: TaskDecomposition,
      role: :input
    )
    toon_output = Sorbet::Toon.encode(
      output_values,
      signature: TaskDecomposition,
      role: :output
    )
    toon_payload = "#{toon_input}\n\n#{toon_output}"

    json_chars = json_payload.length
    toon_chars = toon_payload.length
    savings = ((1 - toon_chars.to_f / json_chars) * 100).round(1)

    {
      json_chars: json_chars,
      toon_chars: toon_chars,
      savings_pct: savings,
      json_payload: json_payload,
      toon_payload: toon_payload
    }
  end

  def test_model(model)
    puts "\nTesting: #{model}"
    puts "-" * 60

    @results[:models][model] = {}

    FORMAT_COMBINATIONS.each do |combo|
      test_format(model, combo)
    end
  end

  def test_format(model, combo)
    schema_format = combo[:schema_format]
    data_format = combo[:data_format]
    combo_key = combo[:key]
    label = "#{combo[:schema_label]} + #{combo[:data_label]}"
    puts "  #{label}..."

    result_key = (@results[:models][model][combo_key] ||= {})
    result_key.merge!(
      success: false,
      response_time: 0.0,
      cost: 0.0,
      tokens: { input: 0, output: 0 },
      error: nil
    )

    begin
      # Configure LM with Enhanced Prompting and specified schema format
      lm = create_lm_for_model(model, schema_format: schema_format, data_format: data_format)
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

        unless predictor.prompt.schema_format == schema_format
          raise "Predictor schema_format mismatch: expected #{schema_format}, got #{predictor.prompt.schema_format}"
        end

        unless predictor.prompt.data_format == data_format
          raise "Predictor data_format mismatch: expected #{data_format}, got #{predictor.prompt.data_format}"
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

      if schema_format == :baml
        estimated_tokens_saved = (@results[:schema_sizes][:json_chars] - @results[:schema_sizes][:baml_chars]) / 4
        @results[:summary][:schema_token_savings] += estimated_tokens_saved
      end

      if data_format == :toon
        estimated_data_tokens_saved = (@results[:data_sizes][:json_chars] - @results[:data_sizes][:toon_chars]) / 4
        @results[:summary][:data_token_savings] += estimated_data_tokens_saved
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

  def create_lm_for_model(model, schema_format: :json, data_format: :json)
    # Always use Enhanced Prompting (structured_outputs: false) for this benchmark
    case model
    when /^gpt-/
      DSPy::LM.new(
        "openai/#{model}",
        api_key: ENV['OPENAI_API_KEY'],
        structured_outputs: false,  # Force Enhanced Prompting
        schema_format: schema_format,
        data_format: data_format
      )
    when /^claude-/
      DSPy::LM.new(
        "anthropic/#{model}",
        api_key: ENV['ANTHROPIC_API_KEY'],
        structured_outputs: false,  # Force Enhanced Prompting
        schema_format: schema_format,
        data_format: data_format
      )
    when /^gemini-/
      DSPy::LM.new(
        "gemini/#{model}",
        api_key: ENV['GEMINI_API_KEY'],
        structured_outputs: false,  # Force Enhanced Prompting
        schema_format: schema_format,
        data_format: data_format
      )
    else
      raise ArgumentError, "Unknown model provider: #{model}"
    end
  end

  def validate_result(result)
    raise "Missing subtasks" unless result.subtasks
    raise "Subtasks must be Task structs" unless result.subtasks.all? { |task| task.is_a?(Task) }

    raise "Missing task_types" unless result.task_types
    raise "Task types must be TaskType enums" unless result.task_types.all? { |type| type.is_a?(TaskType) }

    raise "Missing priority_order" unless result.priority_order
    raise "Priority order must be integers" unless result.priority_order.all? { |value| value.is_a?(Integer) }

    raise "Missing estimated_effort" unless result.estimated_effort
    unless result.estimated_effort.all? { |entry| entry.is_a?(EstimatedEffortWithReasoning) }
      raise "Estimated effort entries must include rationale"
    end

    raise "Missing dependencies" unless result.dependencies
    raise "Dependencies must be Task structs" unless result.dependencies.all? { |task| task.is_a?(Task) }

    raise "Missing agent_requirements" unless result.agent_requirements
  end

  def combo_label(combo_key)
    combo = FORMAT_COMBINATIONS.find { |c| c[:key] == combo_key.to_s }
    combo ? "#{combo[:schema_label]} + #{combo[:data_label]}" : combo_key.to_s
  end

  def benchmark_input_values
    {
      topic: "Sustainable technology adoption in developing countries",
      context: "Focus on practical implementation challenges and success stories",
      complexity_level: ComplexityLevel::Intermediate
    }
  end

  def sample_output_values
    {
      subtasks: [
        Task.new(
          name: "Scope research agenda",
          objective: "Define target regions, technologies, and evaluation criteria",
          success_metric: "Scope brief approved by stakeholders"
        ),
        Task.new(
          name: "Map stakeholders",
          objective: "Identify implementers, funders, regulators, and community partners",
          success_metric: "Stakeholder registry with owner + influence score"
        ),
        Task.new(
          name: "Extract success patterns",
          objective: "Synthesize lessons from high-performing deployments",
          success_metric: "Playbook of 5+ actionable patterns"
        )
      ],
      task_types: [
        TaskType::Planning,
        TaskType::Investigation,
        TaskType::Synthesis
      ],
      priority_order: [1, 2, 3],
      estimated_effort: [
        EstimatedEffortWithReasoning.new(hours: 6, rationale: "Desk research plus expert interviews"),
        EstimatedEffortWithReasoning.new(hours: 8, rationale: "Field calls across three regions"),
        EstimatedEffortWithReasoning.new(hours: 5, rationale: "Collaborative synthesis workshop")
      ],
      dependencies: [
        Task.new(
          name: "Collect baseline data",
          objective: "Gather socioeconomic and infrastructure data per region",
          success_metric: "Baseline dataset with data quality checks"
        ),
        Task.new(
          name: "Secure stakeholder buy-in",
          objective: "Validate scope with regulators and communities",
          success_metric: "Sign-offs from key representatives"
        )
      ],
      agent_requirements: [
        "Energy systems researcher",
        "Field program manager",
        "Policy liaison"
      ]
    }
  end

  def gather_models
    models = []
    models.concat(OPENAI_MODELS) if ENV['OPENAI_API_KEY']
    models.concat(ANTHROPIC_MODELS) if ENV['ANTHROPIC_API_KEY']
    models.concat(GOOGLE_MODELS) if ENV['GEMINI_API_KEY']
    models
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

    if summary[:schema_token_savings] > 0 || summary[:data_token_savings] > 0
      puts "\n💰 Token Savings Estimates:"
      if summary[:schema_token_savings] > 0
        puts "  Schema (BAML vs JSON): ~#{summary[:schema_token_savings]} tokens saved per run"
      end
      if summary[:data_token_savings] > 0
        puts "  Data (TOON vs JSON): ~#{summary[:data_token_savings]} tokens saved per run"
      end
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
        format_display = combo_label(format_name)

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
      csv << ['Model', 'Format Combination', 'Success', 'Response Time (ms)', 'Cost ($)', 'Input Tokens', 'Output Tokens', 'Total Tokens', 'Error']

      # Data rows
      @results[:models].each do |model, formats|
        formats.each do |format_name, data|
          csv << [
            model,
            combo_label(format_name),
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
      Schema & Data Format Comparison
      ===============================

      JSON Schema (Input + Output): #{@results[:schema_sizes][:json_chars]} chars
      BAML Schema (Input + Output): #{@results[:schema_sizes][:baml_chars]} chars
      Schema Token Savings: #{@results[:schema_sizes][:savings_pct]}%

      JSON Data Payload (sample request): #{@results[:data_sizes][:json_chars]} chars
      TOON Data Payload (sample request): #{@results[:data_sizes][:toon_chars]} chars
      Data Token Savings: #{@results[:data_sizes][:savings_pct]}%

      JSON Input Schema:
      #{@results[:schema_sizes][:json_input]}

      JSON Output Schema:
      #{@results[:schema_sizes][:json_output]}

      BAML Input Schema:
      #{@results[:schema_sizes][:baml_input]}

      BAML Output Schema:
      #{@results[:schema_sizes][:baml_output]}

      JSON Data Payload:
      #{@results[:data_sizes][:json_payload]}

      TOON Data Payload:
      #{@results[:data_sizes][:toon_payload]}
    COMPARISON
    puts "📄 Schema/data comparison exported to: #{schema_filename}"
  end

  def export_prompt_analysis_results
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    json_filename = "schema_data_benchmark_#{timestamp}.json"
    File.write(json_filename, JSON.pretty_generate(@results))
    puts "📊 Prompt analysis JSON exported to: #{json_filename}"

    csv_filename = "schema_data_benchmark_#{timestamp}.csv"
    CSV.open(csv_filename, 'w') do |csv|
      csv << ['Schema Format', 'Data Format', 'System Characters', 'User Characters', 'Total Characters', 'Estimated Tokens']
      @results[:prompt_analysis].each do |entry|
        csv << [
          entry[:schema_label],
          entry[:data_label],
          entry[:system_chars],
          entry[:user_chars],
          entry[:total_chars],
          entry[:estimated_tokens]
        ]
      end
    end
    puts "📊 Prompt analysis CSV exported to: #{csv_filename}"

    comparison_filename = "schema_data_comparison_#{timestamp}.txt"
    baseline = @results[:prompt_analysis].find { |entry| entry[:schema_format] == :json && entry[:data_format] == :json }
    File.write(comparison_filename, <<~TEXT)
      Prompt Token Estimates (Enhanced Prompting)
      ==========================================

      Baseline (JSON Schema + JSON Data): #{baseline ? baseline[:estimated_tokens] : 'N/A'} tokens

      #{@results[:prompt_analysis].map do |entry|
        delta = baseline ? entry[:estimated_tokens] - baseline[:estimated_tokens] : 0
        label = "#{entry[:schema_label]} + #{entry[:data_label]}"
        "- #{label.ljust(40)} : #{entry[:estimated_tokens]} tokens (Δ #{delta >= 0 ? '+' : ''}#{delta})"
      end.join("\n")}

      Schema Savings: #{@results[:schema_sizes][:savings_pct]}%
      Data Savings: #{@results[:data_sizes][:savings_pct]}%
    TEXT
    puts "📄 Prompt comparison exported to: #{comparison_filename}"
  end
end

# Run benchmark if executed directly
if __FILE__ == $0
  benchmark = BAMLvsJSONBenchmark.new
  benchmark.run_benchmark
end
