# frozen_string_literal: true

require "sorbet-runtime"
require_relative "adapters/openai/schema_converter"
require_relative "adapters/gemini/schema_converter"

module DSPy
  class LM
    # JSON extraction strategy with provider-specific handling
    class JSONStrategy
      extend T::Sig

      sig { params(adapter: T.untyped, signature_class: T.class_of(DSPy::Signature)).void }
      def initialize(adapter, signature_class)
        @adapter = adapter
        @signature_class = signature_class
      end

      # Prepare request with provider-specific JSON extraction parameters
      sig { params(messages: T::Array[T::Hash[Symbol, T.untyped]], request_params: T::Hash[Symbol, T.untyped]).void }
      def prepare_request(messages, request_params)
        adapter_class_name = adapter.class.name

        if adapter_class_name.include?('OpenAIAdapter') || adapter_class_name.include?('OllamaAdapter')
          prepare_openai_request(request_params)
        elsif adapter_class_name.include?('AnthropicAdapter')
          prepare_anthropic_request(messages, request_params)
        elsif adapter_class_name.include?('GeminiAdapter')
          prepare_gemini_request(request_params)
        end
        # Unknown provider - no special handling
      end

      # Extract JSON from response based on provider
      sig { params(response: DSPy::LM::Response).returns(T.nilable(String)) }
      def extract_json(response)
        adapter_class_name = adapter.class.name

        if adapter_class_name.include?('OpenAIAdapter') || adapter_class_name.include?('OllamaAdapter')
          # OpenAI/Ollama: try to extract JSON from various formats
          extract_json_from_content(response.content)
        elsif adapter_class_name.include?('AnthropicAdapter')
          # Anthropic: try tool use first, fall back to content extraction
          extracted = extract_anthropic_tool_json(response)
          extracted || extract_json_from_content(response.content)
        elsif adapter_class_name.include?('GeminiAdapter')
          # Gemini: try to extract JSON from various formats
          extract_json_from_content(response.content)
        else
          # Unknown provider: try to extract JSON
          extract_json_from_content(response.content)
        end
      end

      sig { returns(String) }
      def name
        'json'
      end

      private

      attr_reader :adapter, :signature_class

      # OpenAI/Ollama preparation
      sig { params(request_params: T::Hash[Symbol, T.untyped]).void }
      def prepare_openai_request(request_params)
        # Check if structured outputs are supported
        if adapter.instance_variable_get(:@structured_outputs_enabled) &&
           DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?(adapter.model)
          response_format = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(signature_class)
          request_params[:response_format] = response_format
        end
      end

      # Anthropic preparation
      sig { params(messages: T::Array[T::Hash[Symbol, T.untyped]], request_params: T::Hash[Symbol, T.untyped]).void }
      def prepare_anthropic_request(messages, request_params)
        # Convert signature to tool schema
        tool_schema = convert_to_anthropic_tool_schema

        # Add tool definition
        request_params[:tools] = [tool_schema]

        # Force tool use
        request_params[:tool_choice] = {
          type: "tool",
          name: "json_output"
        }

        # Update last user message
        if messages.any? && messages.last[:role] == "user"
          messages.last[:content] += "\n\nPlease use the json_output tool to provide your response."
        end
      end

      # Gemini preparation
      sig { params(request_params: T::Hash[Symbol, T.untyped]).void }
      def prepare_gemini_request(request_params)
        # Check if structured outputs are supported
        if adapter.instance_variable_get(:@structured_outputs_enabled) &&
           DSPy::LM::Adapters::Gemini::SchemaConverter.supports_structured_outputs?(adapter.model)
          schema = DSPy::LM::Adapters::Gemini::SchemaConverter.to_gemini_format(signature_class)

          request_params[:generation_config] = {
            response_mime_type: "application/json",
            response_json_schema: schema
          }
        end
      end

      # Convert signature to Anthropic tool schema
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def convert_to_anthropic_tool_schema
        output_fields = signature_class.output_field_descriptors

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

      # Build JSON schema properties from output fields
      sig { params(fields: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
      def build_properties_from_fields(fields)
        properties = {}
        fields.each do |field_name, descriptor|
          properties[field_name.to_s] = DSPy::TypeSystem::SorbetJsonSchema.type_to_json_schema(descriptor.type)
        end
        properties
      end

      # Extract JSON from Anthropic tool use response
      sig { params(response: DSPy::LM::Response).returns(T.nilable(String)) }
      def extract_anthropic_tool_json(response)
        # Check for tool calls in metadata
        if response.metadata.respond_to?(:tool_calls) && response.metadata.tool_calls
          tool_calls = response.metadata.tool_calls
          if tool_calls.is_a?(Array) && !tool_calls.empty?
            first_call = tool_calls.first
            if first_call[:name] == "json_output" && first_call[:input]
              return JSON.generate(first_call[:input])
            end
          end
        end

        nil
      end

      # Extract JSON from content that may contain markdown or plain JSON
      sig { params(content: String).returns(String) }
      def extract_json_from_content(content)
        return content if content.nil? || content.empty?

        # Try 1: Check for ```json code block (with or without preceding text)
        if content.include?('```json')
          json_match = content.match(/```json\s*\n(.*?)\n```/m)
          return json_match[1].strip if json_match
        end

        # Try 2: Check for generic ``` code block
        if content.include?('```')
          code_match = content.match(/```\s*\n(.*?)\n```/m)
          if code_match
            potential_json = code_match[1].strip
            # Verify it's JSON
            begin
              JSON.parse(potential_json)
              return potential_json
            rescue JSON::ParserError
              # Not valid JSON, continue
            end
          end
        end

        # Try 3: Try parsing entire content as JSON
        begin
          JSON.parse(content)
          return content
        rescue JSON::ParserError
          # Not pure JSON, try extracting
        end

        # Try 4: Look for JSON object pattern in text (greedy match for nested objects)
        json_pattern = /\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}/m
        json_match = content.match(json_pattern)
        if json_match
          potential_json = json_match[0]
          begin
            JSON.parse(potential_json)
            return potential_json
          rescue JSON::ParserError
            # Not valid JSON
          end
        end

        # Return content as-is if no JSON found
        content
      end
    end
  end
end
