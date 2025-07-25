# frozen_string_literal: true

require "sorbet-runtime"
require_relative "strategies/base_strategy"
require_relative "strategies/openai_structured_output_strategy"
require_relative "strategies/anthropic_tool_use_strategy"
require_relative "strategies/anthropic_extraction_strategy"
require_relative "strategies/enhanced_prompting_strategy"

module DSPy
  class LM
    # Selects the best JSON extraction strategy based on the adapter and capabilities
    class StrategySelector
      extend T::Sig

      # Available strategies in order of registration
      STRATEGIES = [
        Strategies::OpenAIStructuredOutputStrategy,
        Strategies::AnthropicToolUseStrategy,
        Strategies::AnthropicExtractionStrategy,
        Strategies::EnhancedPromptingStrategy
      ].freeze

      sig { params(adapter: DSPy::LM::Adapter, signature_class: T.class_of(DSPy::Signature)).void }
      def initialize(adapter, signature_class)
        @adapter = adapter
        @signature_class = signature_class
        @strategies = build_strategies
      end

      # Select the best available strategy
      sig { returns(Strategies::BaseStrategy) }
      def select
        # Allow manual override via configuration
        if DSPy.config.structured_outputs.strategy
          strategy = select_strategy_from_preference(DSPy.config.structured_outputs.strategy)
          return strategy if strategy&.available?
          
          # If strict strategy not available, fall back to compatible for Strict preference
          if is_strict_preference?(DSPy.config.structured_outputs.strategy)
            compatible_strategy = find_strategy_by_name("enhanced_prompting")
            return compatible_strategy if compatible_strategy&.available?
          end
          
          DSPy.logger.warn("No available strategy found for preference '#{DSPy.config.structured_outputs.strategy}'")
        end

        # Select the highest priority available strategy
        available_strategies = @strategies.select(&:available?)
        
        if available_strategies.empty?
          raise "No JSON extraction strategies available for #{@adapter.class}"
        end

        selected = available_strategies.max_by(&:priority)
        
        DSPy.logger.debug("Selected JSON extraction strategy: #{selected.name}")
        selected
      end

      # Get all available strategies
      sig { returns(T::Array[Strategies::BaseStrategy]) }
      def available_strategies
        @strategies.select(&:available?)
      end

      # Check if a specific strategy is available
      sig { params(strategy_name: String).returns(T::Boolean) }
      def strategy_available?(strategy_name)
        strategy = find_strategy_by_name(strategy_name)
        strategy&.available? || false
      end

      private

      # Select internal strategy based on user preference
      sig { params(preference: DSPy::Strategy).returns(T.nilable(Strategies::BaseStrategy)) }
      def select_strategy_from_preference(preference)
        case preference
        when DSPy::Strategy::Strict
          # Try provider-optimized strategies first
          select_provider_optimized_strategy
        when DSPy::Strategy::Compatible
          # Use enhanced prompting
          find_strategy_by_name("enhanced_prompting")
        else
          nil
        end
      end
      
      # Check if preference is for strict (provider-optimized) strategies
      sig { params(preference: DSPy::Strategy).returns(T::Boolean) }
      def is_strict_preference?(preference)
        preference == DSPy::Strategy::Strict
      end
      
      # Select the best provider-optimized strategy for the current adapter
      sig { returns(T.nilable(Strategies::BaseStrategy)) }
      def select_provider_optimized_strategy
        # Try OpenAI structured output first
        openai_strategy = find_strategy_by_name("openai_structured_output")
        return openai_strategy if openai_strategy&.available?
        
        # Try Anthropic tool use first
        anthropic_tool_strategy = find_strategy_by_name("anthropic_tool_use")
        return anthropic_tool_strategy if anthropic_tool_strategy&.available?
        
        # Fall back to Anthropic extraction
        anthropic_strategy = find_strategy_by_name("anthropic_extraction")
        return anthropic_strategy if anthropic_strategy&.available?
        
        # No provider-specific strategy available
        nil
      end

      sig { returns(T::Array[Strategies::BaseStrategy]) }
      def build_strategies
        STRATEGIES.map { |klass| klass.new(@adapter, @signature_class) }
      end

      sig { params(name: String).returns(T.nilable(Strategies::BaseStrategy)) }
      def find_strategy_by_name(name)
        @strategies.find { |s| s.name == name }
      end
    end
  end
end