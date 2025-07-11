# frozen_string_literal: true

require "sorbet-runtime"
require_relative "strategies/base_strategy"
require_relative "strategies/openai_structured_output_strategy"
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
          strategy_name = if DSPy.config.structured_outputs.strategy.respond_to?(:serialize)
                           # Handle enum
                           DSPy.config.structured_outputs.strategy.serialize
                         else
                           # Handle string (backward compatibility)
                           DSPy.config.structured_outputs.strategy.to_s
                         end
          
          strategy = find_strategy_by_name(strategy_name)
          return strategy if strategy&.available?
          
          DSPy.logger.warn("Requested strategy '#{strategy_name}' is not available")
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