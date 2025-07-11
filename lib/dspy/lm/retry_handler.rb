# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class LM
    # Handles retry logic with progressive fallback strategies
    class RetryHandler
      extend T::Sig

      MAX_RETRIES = 3
      BACKOFF_BASE = 0.5 # seconds

      sig { params(adapter: DSPy::LM::Adapter, signature_class: T.class_of(DSPy::Signature)).void }
      def initialize(adapter, signature_class)
        @adapter = adapter
        @signature_class = signature_class
        @attempt = 0
      end

      # Execute a block with retry logic and progressive fallback
      sig do
        type_parameters(:T)
          .params(
            initial_strategy: Strategies::BaseStrategy,
            block: T.proc.params(strategy: Strategies::BaseStrategy).returns(T.type_parameter(:T))
          )
          .returns(T.type_parameter(:T))
      end
      def with_retry(initial_strategy, &block)
        strategies = build_fallback_chain(initial_strategy)
        last_error = nil

        strategies.each do |strategy|
          retry_count = 0
          
          begin
            @attempt += 1
            DSPy.logger.debug("Attempting with strategy: #{strategy.name} (attempt #{@attempt})")
            
            result = yield(strategy)
            
            # Success! Reset attempt counter for next time
            @attempt = 0
            return result
            
          rescue JSON::ParserError, StandardError => e
            last_error = e
            
            # Let strategy handle the error first
            if strategy.handle_error(e)
              DSPy.logger.info("Strategy #{strategy.name} handled error, will try next strategy")
              next # Try next strategy
            end
            
            # Try retrying with the same strategy
            if retry_count < max_retries_for_strategy(strategy)
              retry_count += 1
              backoff_time = calculate_backoff(retry_count)
              
              DSPy.logger.warn(
                "Retrying #{strategy.name} after error (attempt #{retry_count}/#{max_retries_for_strategy(strategy)}): #{e.message}"
              )
              
              sleep(backoff_time) if backoff_time > 0
              retry
            else
              DSPy.logger.info("Max retries reached for #{strategy.name}, trying next strategy")
              next # Try next strategy
            end
          end
        end

        # All strategies exhausted
        DSPy.logger.error("All strategies exhausted after #{@attempt} total attempts")
        raise last_error || StandardError.new("All JSON extraction strategies failed")
      end

      private

      # Build a chain of strategies to try in order
      sig { params(initial_strategy: Strategies::BaseStrategy).returns(T::Array[Strategies::BaseStrategy]) }
      def build_fallback_chain(initial_strategy)
        selector = StrategySelector.new(@adapter, @signature_class)
        all_strategies = selector.available_strategies.sort_by(&:priority).reverse
        
        # Start with the requested strategy, then try others
        chain = [initial_strategy]
        chain.concat(all_strategies.reject { |s| s.name == initial_strategy.name })
        
        chain
      end

      # Different strategies get different retry counts
      sig { params(strategy: Strategies::BaseStrategy).returns(Integer) }
      def max_retries_for_strategy(strategy)
        case strategy.name
        when "openai_structured_output"
          1 # Structured outputs rarely benefit from retries
        when "anthropic_extraction"
          2 # Anthropic can be a bit more variable
        else
          MAX_RETRIES # Enhanced prompting might need more attempts
        end
      end

      # Calculate exponential backoff with jitter
      sig { params(attempt: Integer).returns(Float) }
      def calculate_backoff(attempt)
        return 0.0 if DSPy.config.test_mode # No sleep in tests
        
        base_delay = BACKOFF_BASE * (2 ** (attempt - 1))
        jitter = rand * 0.1 * base_delay
        
        [base_delay + jitter, 10.0].min # Cap at 10 seconds
      end
    end
  end
end