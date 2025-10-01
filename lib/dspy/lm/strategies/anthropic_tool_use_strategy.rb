# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class LM
    module Strategies
      # Strategy for using Anthropic's tool use feature for guaranteed JSON output
      class AnthropicToolUseStrategy < BaseStrategy
        extend T::Sig

        sig { override.returns(T::Boolean) }
        def available?
          # Only available for Anthropic adapters with models that support tool use
          adapter.is_a?(DSPy::LM::AnthropicAdapter) && supports_tool_use?
        end

        sig { override.returns(Integer) }
        def priority
          95 # Higher priority than extraction strategy - tool use is more reliable
        end

        sig { override.returns(String) }
        def name
          "anthropic_tool_use"
        end

        sig { override.params(messages: T::Array[T::Hash[Symbol, String]], request_params: T::Hash[Symbol, T.untyped]).void }
        def prepare_request(messages, request_params)
          # Convert signature output schema to Anthropic tool format
          tool_schema = convert_to_tool_schema
          
          # Add the tool definition to request params
          request_params[:tools] = [tool_schema]
          
          # Force the model to use our tool
          request_params[:tool_choice] = {
            type: "tool",
            name: "json_output"
          }
          
          # Update the last user message to request tool use
          if messages.any? && messages.last[:role] == "user"
            messages.last[:content] += "\n\nPlease use the json_output tool to provide your response."
          end
        end

        sig { override.params(response: DSPy::LM::Response).returns(T.nilable(String)) }
        def extract_json(response)
          # Extract JSON from tool use response
          begin
            # Check for tool calls in metadata first (this is the primary method)
            if response.metadata.respond_to?(:tool_calls) && response.metadata.tool_calls
              tool_calls = response.metadata.tool_calls
              if tool_calls.is_a?(Array) && !tool_calls.empty?
                first_call = tool_calls.first
                if first_call[:name] == "json_output" && first_call[:input]
                  json_result = JSON.generate(first_call[:input])
                  return json_result
                end
              end
            end
            
            # Fallback: try to extract from content if it contains tool use blocks
            content = response.content
            if content && !content.empty? && content.include?("<tool_use>")
              tool_content = content[/<tool_use>.*?<\/tool_use>/m]
              if tool_content
                json_match = tool_content[/<input>(.*?)<\/input>/m, 1]
                return json_match.strip if json_match
              end
            end
            
            nil
          rescue => e
            DSPy.logger.debug("Failed to extract tool use JSON: #{e.message}")
            nil
          end
        end

        sig { override.params(error: StandardError).returns(T::Boolean) }
        def handle_error(error)
          # Tool use errors should trigger fallback to extraction strategy
          if error.message.include?("tool") || error.message.include?("invalid_request_error")
            DSPy.logger.warn("Anthropic tool use failed: #{error.message}")
            true # We handled it, try next strategy
          else
            false # Let retry handler deal with it
          end
        end

        private

        sig { returns(T::Boolean) }
        def supports_tool_use?
          # Check if model supports tool use
          # Claude 3 models (Opus, Sonnet, Haiku) support tool use
          model = adapter.model.downcase
          model.include?("claude-3") || model.include?("claude-3.5")
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def convert_to_tool_schema
          # Get output fields from signature
          output_fields = signature_class.output_field_descriptors
          
          # Convert to Anthropic tool format
          {
            name: "json_output",
            description: "Output the result in the required JSON format",
            input_schema: {
              type: "object",
              properties: build_properties_from_fields(output_fields),
              required: output_fields.keys.map(&:to_s)
            }
          }
        end

        sig { params(fields: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
        def build_properties_from_fields(fields)
          properties = {}

          fields.each do |field_name, descriptor|
            properties[field_name.to_s] = DSPy::TypeSystem::SorbetJsonSchema.type_to_json_schema(descriptor.type)
          end

          properties
        end
      end
    end
  end
end