# frozen_string_literal: true

require 'sorbet-runtime'

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
  end
end