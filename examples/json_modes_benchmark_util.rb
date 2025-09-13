# frozen_string_literal: true

require 'sorbet-runtime'
require 'benchmark'

# Utility class for JSON extraction modes benchmarking
class JSONModesBenchmark
  extend T::Sig

  # Available extraction strategies
  STRATEGIES = T.let([
    'enhanced_prompting',
    'openai_structured_output', 
    'anthropic_tool_use',
    'anthropic_extraction',
    'gemini_structured_output'
  ].freeze, T::Array[String])

  # Benchmark result data structure
  class BenchmarkResult < T::Struct
    extend T::Sig

    const :strategy, String
    const :model, String
    const :duration_ms, Float
    const :success, T::Boolean
    const :input_tokens, T.nilable(Integer), default: nil
    const :output_tokens, T.nilable(Integer), default: nil
    const :total_tokens, T.nilable(Integer), default: nil
    const :error_message, T.nilable(String), default: nil
    const :timestamp, Time, default: Time.now

    sig { returns(Float) }
    def tokens_per_second
      return 0.0 if duration_ms.zero? || total_tokens.nil?
      (total_tokens / duration_ms) * 1000
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        strategy: strategy,
        model: model,
        duration_ms: duration_ms,
        success: success,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: total_tokens,
        tokens_per_second: tokens_per_second,
        error_message: error_message,
        timestamp: timestamp
      }
    end
  end

  # Collection of benchmark results
  class BenchmarkResults < T::Struct
    extend T::Sig

    const :results, T::Array[BenchmarkResult], default: []
    const :started_at, Time, default: Time.now
    const :completed_at, T.nilable(Time), default: nil

    sig { params(result: BenchmarkResult).void }
    def add_result(result)
      @results = results + [result]
    end

    sig { void }
    def mark_completed!
      @completed_at = Time.now
    end

    sig { returns(Float) }
    def total_duration_ms
      return 0.0 if results.empty?
      results.sum(&:duration_ms)
    end

    sig { returns(Float) }
    def success_rate
      return 0.0 if results.empty?
      successful_count = results.count(&:success)
      (successful_count.to_f / results.length) * 100
    end

    sig { returns(T::Hash[String, T::Array[BenchmarkResult]]) }
    def group_by_strategy
      results.group_by(&:strategy)
    end

    sig { returns(T::Hash[String, T::Array[BenchmarkResult]]) }
    def group_by_model
      results.group_by(&:model)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def summary
      {
        total_tests: results.length,
        success_rate: success_rate,
        total_duration_ms: total_duration_ms,
        avg_duration_ms: results.empty? ? 0.0 : total_duration_ms / results.length,
        total_tokens: results.sum { |r| r.total_tokens || 0 },
        avg_tokens_per_second: results.empty? ? 0.0 : results.sum(&:tokens_per_second) / results.length,
        started_at: started_at,
        completed_at: completed_at
      }
    end
  end

  class << self
    extend T::Sig

    sig { params(strategy_name: String).void }
    def force_strategy(strategy_name)
      unless STRATEGIES.include?(strategy_name)
        raise ArgumentError, "Unknown strategy: #{strategy_name}. Available: #{STRATEGIES.join(', ')}"
      end

      case strategy_name
      when 'enhanced_prompting'
        DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Compatible }
      when 'openai_structured_output', 'anthropic_tool_use', 'anthropic_extraction', 'gemini_structured_output'
        DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      end

      # Log the forced strategy for verification
      DSPy.logger.info("✓ Forced strategy: #{strategy_name.split('_').map(&:capitalize).join(' ')} (#{get_strategy_type(strategy_name)})")
    end

    sig { params(strategy_name: String).returns(String) }
    def get_strategy_type(strategy_name)
      case strategy_name
      when 'enhanced_prompting'
        'compatible'
      when 'openai_structured_output', 'anthropic_tool_use', 'anthropic_extraction', 'gemini_structured_output'
        'strict'
      else
        'unknown'
      end
    end

    sig { returns(T::Array[String]) }
    def available_strategies
      STRATEGIES.dup
    end

    sig { params(signature_class: T.class_of(DSPy::Signature), providers: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
    def get_strategy_compatibility_matrix(signature_class, providers = ['openai', 'anthropic', 'gemini'])
      matrix = {}

      providers.each do |provider|
        compatible_strategies = []

        STRATEGIES.each do |strategy|
          # Determine compatibility based on strategy and provider
          compatible = case strategy
          when 'enhanced_prompting'
            true # Works with all providers
          when 'openai_structured_output'
            provider == 'openai'
          when 'anthropic_tool_use', 'anthropic_extraction'
            provider == 'anthropic'
          when 'gemini_structured_output'
            provider == 'gemini'
          else
            false
          end

          compatible_strategies << strategy if compatible
        end

        matrix[provider] = compatible_strategies
      end

      matrix
    end

    sig { params(strategy_name: String, model: String, signature_class: T.class_of(DSPy::Signature)).returns(T::Boolean) }
    def strategy_available_for_model?(strategy_name, model, signature_class)
      # Parse provider from model
      provider = model.split('/').first

      # Get compatibility matrix
      matrix = get_strategy_compatibility_matrix(signature_class, [provider])
      compatible_strategies = matrix[provider] || []

      compatible_strategies.include?(strategy_name)
    end

    sig { params(strategy: String, model: String, predictor: DSPy::Predict, query: String, context: T.untyped, user_profile: T.untyped).returns(BenchmarkResult) }
    def run_single_benchmark(strategy, model, predictor, query, context, user_profile)
      # Force the strategy
      force_strategy(strategy)

      start_time = Time.now
      success = false
      error_message = nil
      input_tokens = nil
      output_tokens = nil
      total_tokens = nil

      begin
        # Capture span events to get token usage
        captured_events = []
        original_logger = DSPy.logger

        # Create a custom logger that captures events
        event_capturer = Class.new do
          def initialize(captured_events)
            @captured_events = captured_events
          end

          def info(message)
            @captured_events << message if message.is_a?(String) && message.include?('gen_ai.usage')
          end

          def debug(message); end
          def warn(message); end
          def error(message); end
        end

        DSPy.instance_variable_set(:@logger, event_capturer.new(captured_events))

        # Run the prediction
        result = predictor.call(
          query: query,
          context: context,
          user_profile: user_profile
        )

        success = true

        # Try to extract token usage from the latest LM response
        if DSPy.config.lm.respond_to?(:adapter) && DSPy.config.lm.adapter.respond_to?(:last_response)
          last_response = DSPy.config.lm.adapter.instance_variable_get(:@last_response)
          if last_response && last_response.usage
            usage = last_response.usage
            input_tokens = usage.input_tokens
            output_tokens = usage.output_tokens
            total_tokens = usage.total_tokens
          end
        end

      rescue => e
        success = false
        error_message = e.message
      ensure
        # Restore original logger
        DSPy.instance_variable_set(:@logger, original_logger)
      end

      end_time = Time.now
      duration_ms = ((end_time - start_time) * 1000).round(2)

      BenchmarkResult.new(
        strategy: strategy,
        model: model,
        duration_ms: duration_ms,
        success: success,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: total_tokens,
        error_message: error_message,
        timestamp: start_time
      )
    end

    sig { params(strategies: T::Array[String], models: T::Array[String], signature_class: T.class_of(DSPy::Signature), test_inputs: T::Hash[Symbol, T.untyped]).returns(BenchmarkResults) }
    def run_comprehensive_benchmark(strategies, models, signature_class, test_inputs)
      results = BenchmarkResults.new
      predictor = DSPy::Predict.new(signature_class)

      strategies.each do |strategy|
        models.each do |model|
          # Skip incompatible combinations
          next unless strategy_available_for_model?(strategy, model, signature_class)

          # Configure the LM for this model
          provider = model.split('/').first
          api_key_env = case provider
                       when 'openai' then 'OPENAI_API_KEY'
                       when 'anthropic' then 'ANTHROPIC_API_KEY'
                       when 'gemini' then 'GEMINI_API_KEY'
                       else nil
                       end

          next unless api_key_env && ENV[api_key_env]

          # Create LM with appropriate settings
          lm_options = {}
          lm_options[:structured_outputs] = true if ['openai_structured_output', 'gemini_structured_output'].include?(strategy)

          lm = DSPy::LM.new(model, api_key: ENV[api_key_env], **lm_options)
          DSPy.configure { |c| c.lm = lm }

          # Run the benchmark
          result = run_single_benchmark(
            strategy, 
            model, 
            predictor, 
            test_inputs[:query], 
            test_inputs[:context], 
            test_inputs[:user_profile]
          )

          results.add_result(result)
          
          # Log progress
          status = result.success ? "✓" : "✗"
          DSPy.logger.info("#{status} #{strategy} on #{model}: #{result.duration_ms}ms")
        end
      end

      results.mark_completed!
      results
    end

    sig { params(results: BenchmarkResults).returns(String) }
    def format_benchmark_report(results)
      summary = results.summary
      
      report = []
      report << "# JSON Extraction Modes Benchmark Report"
      report << ""
      report << "## Summary"
      report << "- **Total Tests**: #{summary[:total_tests]}"
      report << "- **Success Rate**: #{summary[:success_rate].round(1)}%"
      report << "- **Total Duration**: #{summary[:total_duration_ms].round(1)}ms"
      report << "- **Average Duration**: #{summary[:avg_duration_ms].round(1)}ms"
      report << "- **Total Tokens**: #{summary[:total_tokens]}"
      report << "- **Average Tokens/sec**: #{summary[:avg_tokens_per_second].round(1)}"
      report << ""

      # Strategy breakdown
      report << "## Results by Strategy"
      results.group_by_strategy.each do |strategy, strategy_results|
        successful = strategy_results.count(&:success)
        avg_duration = strategy_results.sum(&:duration_ms) / strategy_results.length
        
        report << "### #{strategy.split('_').map(&:capitalize).join(' ')}"
        report << "- Success Rate: #{(successful.to_f / strategy_results.length * 100).round(1)}%"
        report << "- Average Duration: #{avg_duration.round(1)}ms"
        report << ""
      end

      # Model breakdown
      report << "## Results by Model"
      results.group_by_model.each do |model, model_results|
        successful = model_results.count(&:success)
        avg_duration = model_results.sum(&:duration_ms) / model_results.length
        
        report << "### #{model}"
        report << "- Success Rate: #{(successful.to_f / model_results.length * 100).round(1)}%"
        report << "- Average Duration: #{avg_duration.round(1)}ms"
        report << ""
      end

      report.join("\n")
    end
  end
end