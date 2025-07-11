# frozen_string_literal: true

require_relative "base_strategy"

module DSPy
  class LM
    module Strategies
      # Strategy for using OpenAI's native structured output feature
      class OpenAIStructuredOutputStrategy < BaseStrategy
        extend T::Sig

        sig { override.returns(T::Boolean) }
        def available?
          # Check if adapter is OpenAI and supports structured outputs
          return false unless adapter.is_a?(DSPy::LM::OpenAIAdapter)
          return false unless adapter.instance_variable_get(:@structured_outputs_enabled)
          
          DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?(adapter.model)
        end

        sig { override.returns(Integer) }
        def priority
          100 # Highest priority - native structured outputs are most reliable
        end

        sig { override.returns(String) }
        def name
          "openai_structured_output"
        end

        sig { override.params(messages: T::Array[T::Hash[Symbol, String]], request_params: T::Hash[Symbol, T.untyped]).void }
        def prepare_request(messages, request_params)
          # Add structured output format to request
          response_format = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(signature_class)
          request_params[:response_format] = response_format
        end

        sig { override.params(response: DSPy::LM::Response).returns(T.nilable(String)) }
        def extract_json(response)
          # With structured outputs, the response should already be valid JSON
          # Just return the content as-is
          response.content
        end

        sig { override.params(error: StandardError).returns(T::Boolean) }
        def handle_error(error)
          # Handle OpenAI-specific structured output errors
          if error.message.include?("response_format") || error.message.include?("Invalid schema")
            # Log the error and return true to indicate we handled it
            # This allows fallback to another strategy
            DSPy.logger.warn("OpenAI structured output failed: #{error.message}")
            true
          else
            false
          end
        end
      end
    end
  end
end