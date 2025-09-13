# frozen_string_literal: true

require_relative "base_strategy"
require_relative "../adapters/gemini/schema_converter"

module DSPy
  class LM
    module Strategies
      # Strategy for using Gemini's native structured output feature
      class GeminiStructuredOutputStrategy < BaseStrategy
        extend T::Sig

        sig { override.returns(T::Boolean) }
        def available?
          # Check if adapter is Gemini and supports structured outputs
          return false unless adapter.is_a?(DSPy::LM::GeminiAdapter)
          return false unless adapter.instance_variable_get(:@structured_outputs_enabled)
          
          DSPy::LM::Adapters::Gemini::SchemaConverter.supports_structured_outputs?(adapter.model)
        end

        sig { override.returns(Integer) }
        def priority
          100 # Highest priority - native structured outputs are most reliable
        end

        sig { override.returns(String) }
        def name
          "gemini_structured_output"
        end

        sig { override.params(messages: T::Array[T::Hash[Symbol, String]], request_params: T::Hash[Symbol, T.untyped]).void }
        def prepare_request(messages, request_params)
          # Convert signature to Gemini schema format
          schema = DSPy::LM::Adapters::Gemini::SchemaConverter.to_gemini_format(signature_class)
          
          # Add generation_config for structured output
          request_params[:generation_config] = {
            response_mime_type: "application/json",
            response_schema: schema
          }
        end

        sig { override.params(response: DSPy::LM::Response).returns(T.nilable(String)) }
        def extract_json(response)
          # With Gemini structured outputs, the response should already be valid JSON
          # Just return the content as-is
          response.content
        end

        sig { override.params(error: StandardError).returns(T::Boolean) }
        def handle_error(error)
          # Handle Gemini-specific structured output errors
          error_msg = error.message.to_s.downcase
          if error_msg.include?("schema") || error_msg.include?("generation_config") || error_msg.include?("response_schema")
            # Log the error and return true to indicate we handled it
            # This allows fallback to another strategy
            DSPy.logger.warn("Gemini structured output failed: #{error.message}")
            true
          else
            false
          end
        end
      end
    end
  end
end