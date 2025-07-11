# frozen_string_literal: true

require_relative "base_strategy"

module DSPy
  class LM
    module Strategies
      # Strategy for using Anthropic's enhanced JSON extraction patterns
      class AnthropicExtractionStrategy < BaseStrategy
        extend T::Sig

        sig { override.returns(T::Boolean) }
        def available?
          adapter.is_a?(DSPy::LM::AnthropicAdapter)
        end

        sig { override.returns(Integer) }
        def priority
          90 # High priority - Anthropic's extraction is very reliable
        end

        sig { override.returns(String) }
        def name
          "anthropic_extraction"
        end

        sig { override.params(messages: T::Array[T::Hash[Symbol, String]], request_params: T::Hash[Symbol, T.untyped]).void }
        def prepare_request(messages, request_params)
          # Anthropic adapter already handles JSON optimization in prepare_messages_for_json
          # No additional preparation needed here
        end

        sig { override.params(response: DSPy::LM::Response).returns(T.nilable(String)) }
        def extract_json(response)
          # Use Anthropic's specialized extraction method if available
          if adapter.respond_to?(:extract_json_from_response)
            adapter.extract_json_from_response(response.content)
          else
            # Fallback to basic extraction
            extract_json_fallback(response.content)
          end
        end

        private

        sig { params(content: T.nilable(String)).returns(T.nilable(String)) }
        def extract_json_fallback(content)
          return nil if content.nil?

          # Try the 4 patterns Anthropic adapter uses
          # Pattern 1: ```json blocks
          if content.include?('```json')
            return content.split('```json').last.split('```').first.strip
          end

          # Pattern 2: ## Output values header
          if content.include?('## Output values')
            json_part = content.split('## Output values').last
            if json_part.include?('```')
              return json_part.split('```')[1].strip
            end
          end

          # Pattern 3: Generic code blocks
          if content.include?('```')
            code_block = content.split('```')[1]
            if code_block && (code_block.strip.start_with?('{') || code_block.strip.start_with?('['))
              return code_block.strip
            end
          end

          # Pattern 4: Already valid JSON
          content.strip if content.strip.start_with?('{') || content.strip.start_with?('[')
        end
      end
    end
  end
end