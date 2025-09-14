#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark'
require 'json'
require 'csv'
require 'dotenv'

# Load environment variables from .env file
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

# Load the TodoListManagementSignature and related structs
require_relative './benchmark_types'

# Configure observability
DSPy::Observability.configure!

class JSONModesBenchmark
  # Model constants for 2025 testing
  OPENAI_MODELS = %w[
    gpt-5 gpt-5-mini gpt-5-nano 
    gpt-4o gpt-4o-mini 
    o1 o1-mini
  ].freeze

  ANTHROPIC_MODELS = %w[
    claude-opus-4.1 claude-sonnet-4 
    claude-3-5-sonnet claude-3-5-haiku
  ].freeze

  GOOGLE_MODELS = %w[
    gemini-1.5-pro gemini-1.5-flash
  ].freeze

  ALL_MODELS = (OPENAI_MODELS + ANTHROPIC_MODELS + GOOGLE_MODELS).freeze

  EXTRACTION_STRATEGIES = %w[
    enhanced_prompting
    openai_structured_output
    anthropic_tool_use
    anthropic_extraction
    gemini_structured_output
  ].freeze

  # Model pricing per 1M tokens (input/output) - September 2025
  MODEL_PRICING = {
    # OpenAI Models
    'gpt-5' => { input: 1.25, output: 10.00 },
    'gpt-5-mini' => { input: 0.15, output: 1.25 },
    'gpt-5-nano' => { input: 0.05, output: 0.25 },
    'gpt-4o' => { input: 2.50, output: 10.00 },
    'gpt-4o-mini' => { input: 0.15, output: 0.60 },
    'o1' => { input: 15.00, output: 60.00 },
    'o1-mini' => { input: 3.00, output: 12.00 },
    
    # Anthropic Models
    'claude-opus-4.1' => { input: 15.00, output: 75.00 },
    'claude-sonnet-4' => { input: 3.00, output: 15.00 },
    'claude-3-5-sonnet' => { input: 3.00, output: 15.00 },
    'claude-3-5-haiku' => { input: 0.80, output: 4.00 },
    
    # Google Models (per official pricing)
    'gemini-1.5-pro' => { input: 1.25, output: 5.00 },
    'gemini-1.5-flash' => { input: 0.075, output: 0.30 },
    'gemini-2.0-flash-exp' => { input: 0.00, output: 0.00 }  # Experimental - free for now
  }.freeze

  def initialize
    @results = {
      combinations: {},
      summary: {
        total_tests: 0,
        successful_tests: 0,
        failed_tests: 0,
        total_cost: 0.0,
        average_response_time: 0.0
      },
      strategy_performance: {},
      model_performance: {}
    }
    
    # Set up observability for metrics collection
    setup_observability
    
    puts "JSON Extraction Modes Benchmark"
    puts "==============================="
    puts "Testing #{ALL_MODELS.length} models with #{EXTRACTION_STRATEGIES.length} strategies"
    puts "Total combinations: #{ALL_MODELS.length * EXTRACTION_STRATEGIES.length}"
    puts
  end

  # Force a specific extraction strategy
  def self.force_strategy(strategy_name)
    case strategy_name
    when 'enhanced_prompting'
      DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Compatible }
      puts "✓ Forced strategy: Enhanced Prompting (compatible)"
      
    when 'openai_structured_output'
      DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      puts "✓ Forced strategy: OpenAI Structured Output (strict)"
      
    when 'anthropic_tool_use'
      DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      puts "✓ Forced strategy: Anthropic Tool Use (strict)"
      
    when 'anthropic_extraction'
      DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      puts "✓ Forced strategy: Anthropic Extraction (strict)"
      
    when 'gemini_structured_output'
      DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      puts "✓ Forced strategy: Gemini Structured Output (strict)"
      
    else
      raise ArgumentError, "Unknown strategy: #{strategy_name}"
    end
  end

  def run_full_benchmark
    puts "🚀 Starting comprehensive benchmark..."
    puts
    
    start_time = Time.now
    
    EXTRACTION_STRATEGIES.each do |strategy|
      puts "\n" + "="*60
      puts "Testing Strategy: #{strategy.upcase}"  
      puts "="*60
      
      @results[:strategy_performance][strategy] = {
        successful_tests: 0,
        failed_tests: 0,
        total_response_time: 0.0,
        total_cost: 0.0,
        compatible_models: [],
        incompatible_models: []
      }
      
      test_strategy(strategy)
    end
    
    end_time = Time.now
    total_duration = end_time - start_time
    
    puts "\n" + "="*60
    puts "BENCHMARK COMPLETE"
    puts "="*60
    puts "Total duration: #{total_duration.round(2)} seconds"
    
    generate_reports
    save_results_to_file
  end

  private

  def setup_observability
    # Subscribe to DSPy events for performance metrics
    @timing_data = {}
    @token_data = {}
    
    DSPy.events.subscribe('lm.raw_chat.start') do |event_name, attributes|
      @timing_data[attributes[:request_id]] = { start_time: Time.now }
    end
    
    DSPy.events.subscribe('lm.raw_chat.complete') do |event_name, attributes|
      if start_data = @timing_data[attributes[:request_id]]
        duration = Time.now - start_data[:start_time]
        start_data[:duration] = duration
        start_data[:model] = attributes[:model]
        start_data[:tokens] = attributes[:usage]&.dig(:total_tokens) || 0
      end
    end
  end

  def test_strategy(strategy)
    JSONModesBenchmark.force_strategy(strategy)
    
    # Test with compatible models first
    compatible_models = get_compatible_models_for_strategy(strategy)
    
    compatible_models.each do |model|
      test_model_strategy_combination(model, strategy)
    end
  end

  def get_compatible_models_for_strategy(strategy)
    case strategy
    when 'enhanced_prompting'
      ALL_MODELS # Works with all models
    when 'openai_structured_output'
      OPENAI_MODELS.select { |m| supports_structured_outputs?(m) }
    when 'anthropic_tool_use', 'anthropic_extraction'
      ANTHROPIC_MODELS
    when 'gemini_structured_output'
      GOOGLE_MODELS.select { |m| supports_gemini_structured_outputs?(m) }
    else
      []
    end
  end

  def supports_structured_outputs?(model)
    # Based on OpenAI structured outputs capability matrix
    structured_output_models = %w[gpt-4o gpt-4o-mini gpt-5 gpt-5-mini gpt-5-nano]
    structured_output_models.include?(model)
  end

  def supports_gemini_structured_outputs?(model)
    # Based on official gemini-ai gem documentation - models with ✅ full schema support
    structured_output_models = %w[
      gemini-1.5-pro
    ]
    structured_output_models.include?(model)
  end

  def test_model_strategy_combination(model, strategy)
    combination_key = "#{model}__#{strategy}"
    
    puts "\n  Testing: #{model} with #{strategy}"
    
    @results[:combinations][combination_key] = {
      model: model,
      strategy: strategy,
      success: false,
      error: nil,
      response_time: 0.0,
      tokens_used: 0,
      cost: 0.0,
      strategy_actually_used: nil
    }
    
    begin
      # Configure the LM for this model
      lm = create_lm_for_model(model)
      return unless lm # Skip if we can't create LM (missing API keys, etc.)
      
      DSPy.configure { |c| c.lm = lm }
      
      # Create predictor and test
      predictor = DSPy::Predict.new(TodoListManagementSignature)
      
      start_time = Time.now
      
      # Capture which strategy was actually selected
      allow_debug_capture do
        result = predictor.call(
          query: "Create a high-priority todo for testing #{model} with #{strategy} strategy",
          context: create_test_context,
          user_profile: create_test_user_profile
        )
        
        end_time = Time.now
        response_time = end_time - start_time
        
        # Validate the result structure
        validate_complex_result(result)
        
        # Record success
        @results[:combinations][combination_key][:success] = true
        @results[:combinations][combination_key][:response_time] = response_time
        @results[:combinations][combination_key][:strategy_actually_used] = extract_strategy_from_logs
        
        # Calculate cost and token usage
        calculate_metrics(combination_key, model, response_time)
        
        @results[:summary][:successful_tests] += 1
        @results[:strategy_performance][strategy][:successful_tests] += 1
        @results[:strategy_performance][strategy][:total_response_time] += response_time
        @results[:strategy_performance][strategy][:compatible_models] << model
        
        puts "    ✅ SUCCESS (#{response_time.round(3)}s)"
      end
      
    rescue => error
      handle_test_error(combination_key, strategy, model, error)
    end
    
    @results[:summary][:total_tests] += 1
  end

  def create_lm_for_model(model)
    provider, model_name = extract_provider_and_model(model)
    
    case provider
    when 'openai'
      return nil unless ENV['OPENAI_API_KEY']
      DSPy::LM.new("openai/#{model_name}", api_key: ENV['OPENAI_API_KEY'])
      
    when 'anthropic' 
      return nil unless ENV['ANTHROPIC_API_KEY']
      # Map our model names to Anthropic's actual model IDs
      anthropic_model = map_to_anthropic_model_id(model_name)
      DSPy::LM.new("anthropic/#{anthropic_model}", api_key: ENV['ANTHROPIC_API_KEY'])
      
    when 'google'
      return nil unless ENV['GOOGLE_API_KEY'] || ENV['GEMINI_API_KEY']
      api_key = ENV['GOOGLE_API_KEY'] || ENV['GEMINI_API_KEY']
      DSPy::LM.new("gemini/#{model_name}", api_key: api_key, structured_outputs: true)
      
    else
      nil
    end
  end

  def extract_provider_and_model(model)
    case model
    when /^gpt-|^o1-/
      ['openai', model]
    when /^claude-/
      ['anthropic', model]
    when /^gemini-/
      ['google', model]
    else
      ['unknown', model]
    end
  end

  def map_to_anthropic_model_id(model_name)
    # Map our test model names to actual Anthropic model IDs
    mapping = {
      'claude-opus-4.1' => 'claude-3-opus-20240229',  # Placeholder - use best available
      'claude-sonnet-4' => 'claude-3-5-sonnet-20240620',  # Placeholder - use best available  
      'claude-3-5-sonnet' => 'claude-3-5-sonnet-20240620',
      'claude-3-5-haiku' => 'claude-3-haiku-20240307'  # Fix: There's no claude-3-5-haiku
    }
    mapping[model_name] || model_name
  end

  def create_test_context
    ProjectContext.new(
      project_id: "benchmark-project",
      active_lists: ["benchmark-todos"],
      available_tags: ["test", "benchmark"]
    )
  end

  def create_test_user_profile
    UserProfile.new(
      user_id: "benchmark-user",
      role: UserRole::Admin,
      timezone: "UTC"
    )
  end

  def validate_complex_result(result)
    # Basic structure validation
    raise "Missing action field" unless result.respond_to?(:action)
    raise "Missing affected_todos field" unless result.respond_to?(:affected_todos)
    raise "Missing summary field" unless result.respond_to?(:summary)
    raise "Missing related_actions field" unless result.respond_to?(:related_actions)
    
    # Type validation
    raise "Action is not a struct" unless result.action.is_a?(T::Struct)
    raise "Affected todos is not an array" unless result.affected_todos.is_a?(Array)
    raise "Related actions is not an array" unless result.related_actions.is_a?(Array)
    
    # Union type discrimination validation
    action_classes = [CreateTodoAction, UpdateTodoAction, DeleteTodoAction, AssignTodoAction]
    raise "Action is not one of expected union types" unless action_classes.any? { |klass| result.action.is_a?(klass) }
  end

  def allow_debug_capture(&block)
    # Temporarily capture debug logs to extract strategy information
    original_logger = DSPy.logger
    captured_logs = []
    
    # Create a custom logger that captures debug messages
    test_logger = Object.new
    def test_logger.debug(message)
      @captured_logs ||= []
      @captured_logs << message
    end
    def test_logger.captured_logs
      @captured_logs || []
    end
    
    # Stub other logger methods
    %i[info warn error fatal].each do |method|
      test_logger.define_singleton_method(method) { |*| }
    end
    
    DSPy.configure { |c| c.logger = test_logger }
    
    result = block.call
    
    @captured_debug_logs = test_logger.captured_logs
    
    DSPy.configure { |c| c.logger = original_logger }
    
    result
  end

  def extract_strategy_from_logs
    return nil unless @captured_debug_logs
    
    strategy_log = @captured_debug_logs.find { |log| log.include?("Selected JSON extraction strategy:") }
    return nil unless strategy_log
    
    strategy_log.match(/Selected JSON extraction strategy: (.+)/)&.[](1)
  end

  def calculate_metrics(combination_key, model, response_time)
    # Get token usage from timing data if available
    recent_timing = @timing_data.values.last
    tokens_used = recent_timing&.dig(:tokens) || estimate_tokens_for_model(model)
    
    @results[:combinations][combination_key][:tokens_used] = tokens_used
    
    # Calculate cost
    pricing = MODEL_PRICING[model]
    if pricing && tokens_used > 0
      # Estimate input/output split (rough approximation)
      input_tokens = (tokens_used * 0.7).round
      output_tokens = (tokens_used * 0.3).round
      
      cost = (input_tokens * pricing[:input] / 1_000_000) + 
             (output_tokens * pricing[:output] / 1_000_000)
             
      @results[:combinations][combination_key][:cost] = cost
      @results[:summary][:total_cost] += cost
    end
  end

  def estimate_tokens_for_model(model)
    # Rough token estimation based on model and our complex signature
    case model
    when /gpt-5/, /claude-opus/
      1500  # Complex models might use more tokens
    when /gpt-4o/, /claude-sonnet/
      1200
    when /mini/, /haiku/
      800
    else
      1000
    end
  end

  def handle_test_error(combination_key, strategy, model, error)
    error_message = error.message.lines.first&.strip || error.class.name
    
    @results[:combinations][combination_key][:error] = error_message
    @results[:summary][:failed_tests] += 1
    @results[:strategy_performance][strategy][:failed_tests] += 1
    @results[:strategy_performance][strategy][:incompatible_models] << model
    
    puts "    ❌ FAILED: #{error_message}"
    
    # Log detailed error for debugging
    puts "       Details: #{error.class}: #{error.message}" if ENV['DEBUG']
  end

  def generate_reports
    puts "\n" + "="*80
    puts "BENCHMARK RESULTS SUMMARY"
    puts "="*80
    
    generate_summary_report
    generate_strategy_performance_report
    generate_model_compatibility_matrix
    generate_cost_analysis
  end

  def generate_summary_report
    puts "\n📊 OVERALL SUMMARY:"
    puts "-" * 40
    puts "Total tests: #{@results[:summary][:total_tests]}"
    puts "Successful: #{@results[:summary][:successful_tests]} (#{success_percentage}%)"
    puts "Failed: #{@results[:summary][:failed_tests]} (#{failure_percentage}%)"
    puts "Total estimated cost: $#{@results[:summary][:total_cost].round(4)}"
  end

  def generate_strategy_performance_report
    puts "\n⚡ STRATEGY PERFORMANCE:"
    puts "-" * 40
    
    EXTRACTION_STRATEGIES.each do |strategy|
      perf = @results[:strategy_performance][strategy]
      next unless perf
      
      success_count = perf[:successful_tests]
      total_count = success_count + perf[:failed_tests]
      success_rate = total_count > 0 ? (success_count.to_f / total_count * 100).round(1) : 0
      avg_time = success_count > 0 ? (perf[:total_response_time] / success_count).round(3) : 0
      
      puts "\n#{strategy.upcase}:"
      puts "  Success rate: #{success_rate}% (#{success_count}/#{total_count})"
      puts "  Avg response time: #{avg_time}s"
      puts "  Compatible models: #{perf[:compatible_models].length}"
      puts "  Estimated cost: $#{perf[:total_cost].round(4)}"
    end
  end

  def generate_model_compatibility_matrix
    puts "\n🔧 MODEL COMPATIBILITY MATRIX:"
    puts "-" * 50
    
    # Create a matrix showing which models work with which strategies
    printf "%-20s", "Model"
    EXTRACTION_STRATEGIES.each { |s| printf "%-12s", s[0..10] }
    puts
    
    puts "-" * (20 + (EXTRACTION_STRATEGIES.length * 12))
    
    ALL_MODELS.each do |model|
      printf "%-20s", model[0..18]
      
      EXTRACTION_STRATEGIES.each do |strategy|
        combination_key = "#{model}__#{strategy}"
        result = @results[:combinations][combination_key]
        
        if result
          status = result[:success] ? "✅" : "❌"
          printf "%-12s", status
        else
          printf "%-12s", "⏭️"  # Skipped
        end
      end
      puts
    end
  end

  def generate_cost_analysis
    puts "\n💰 COST ANALYSIS:"
    puts "-" * 30
    
    # Sort combinations by cost
    cost_sorted = @results[:combinations]
      .select { |k, v| v[:cost] && v[:cost] > 0 }
      .sort_by { |k, v| v[:cost] }
      .reverse
    
    puts "\nTop 10 most expensive combinations:"
    cost_sorted.first(10).each_with_index do |(key, result), idx|
      model, strategy = key.split('__')
      puts "#{idx + 1}. #{model} + #{strategy}: $#{result[:cost].round(6)}"
    end
    
    puts "\nMost cost-effective combinations:"
    cost_sorted.last(5).each_with_index do |(key, result), idx|
      model, strategy = key.split('__')
      puts "#{idx + 1}. #{model} + #{strategy}: $#{result[:cost].round(6)}"
    end
  end

  def save_results_to_file
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    
    # Save detailed JSON results
    json_filename = "benchmark_results_#{timestamp}.json"
    File.write(json_filename, JSON.pretty_generate(@results))
    puts "\n📄 Detailed results saved to: #{json_filename}"
    
    # Save CSV summary for spreadsheet analysis
    csv_filename = "benchmark_summary_#{timestamp}.csv"
    CSV.open(csv_filename, 'w', write_headers: true, headers: %w[Model Strategy Success ResponseTime Tokens Cost Error]) do |csv|
      @results[:combinations].each do |key, result|
        model, strategy = key.split('__')
        csv << [
          model,
          strategy, 
          result[:success],
          result[:response_time],
          result[:tokens_used],
          result[:cost],
          result[:error]
        ]
      end
    end
    puts "📊 CSV summary saved to: #{csv_filename}"
  end

  def success_percentage
    return 0 if @results[:summary][:total_tests] == 0
    (@results[:summary][:successful_tests].to_f / @results[:summary][:total_tests] * 100).round(1)
  end

  def failure_percentage
    return 0 if @results[:summary][:total_tests] == 0  
    (@results[:summary][:failed_tests].to_f / @results[:summary][:total_tests] * 100).round(1)
  end
end

# Run benchmark if this file is executed directly
if __FILE__ == $0
  # Check for required API keys
  required_keys = %w[OPENAI_API_KEY ANTHROPIC_API_KEY]
  optional_keys = %w[GOOGLE_API_KEY GEMINI_API_KEY]  # Either one works for Gemini
  missing_keys = required_keys.reject { |key| ENV[key] }
  
  # Check if at least one Gemini key is present
  gemini_key_present = optional_keys.any? { |key| ENV[key] }
  missing_keys << 'GOOGLE_API_KEY or GEMINI_API_KEY' unless gemini_key_present
  
  if missing_keys.any?
    puts "⚠️  Warning: Missing API keys: #{missing_keys.join(', ')}"
    puts "Some tests will be skipped. Set these environment variables to test all models."
    puts
  end
  
  benchmark = JSONModesBenchmark.new
  benchmark.run_full_benchmark
  
  # Flush observability data before process exits
  DSPy::Observability.flush!
  
  puts "\n🎉 Benchmark complete! Check the generated files for detailed results."
end