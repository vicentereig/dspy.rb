# frozen_string_literal: true

require "sorbet-runtime"

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
          # Anthropic: Beta API returns JSON in content, same as OpenAI/Gemini
          extract_json_from_content(response.content)
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
        begin
          require "dspy/openai"
        rescue LoadError
          msg = <<~MSG
            OpenAI adapter is optional; structured output helpers will be unavailable until the gem is installed.
            Add `gem 'dspy-openai'` to your Gemfile and run `bundle install`.
          MSG
          raise DSPy::LM::MissingAdapterError, msg
        end

        # Check if structured outputs are supported
        if adapter.instance_variable_get(:@structured_outputs_enabled) && DSPy::OpenAI::LM::SchemaConverter.supports_structured_outputs?(adapter.model)
          response_format = DSPy::OpenAI::LM::SchemaConverter.to_openai_format(signature_class)
          request_params[:response_format] = response_format
        end
      end

      # Anthropic preparation
      sig { params(messages: T::Array[T::Hash[Symbol, T.untyped]], request_params: T::Hash[Symbol, T.untyped]).void }
      def prepare_anthropic_request(messages, request_params)
        begin
          require "dspy/anthropic/lm/schema_converter"
        rescue LoadError
          msg = <<~MSG
            Anthropic adapter is optional; structured output helpers will be unavailable until the gem is installed.
            Add `gem 'dspy-anthropic'` to your Gemfile and run `bundle install`.
          MSG
          raise DSPy::LM::MissingAdapterError, msg
        end

        # Only use Beta API structured outputs if enabled (default: true)
        structured_outputs_enabled = adapter.instance_variable_get(:@structured_outputs_enabled)
        structured_outputs_enabled = true if structured_outputs_enabled.nil?

        return unless structured_outputs_enabled

        # Use Anthropic Beta API structured outputs
        schema = DSPy::Anthropic::LM::SchemaConverter.to_beta_format(signature_class)

        request_params[:output_format] = Anthropic::Models::Beta::BetaJSONOutputFormat.new(
          type: :json_schema,
          schema: schema
        )
        request_params[:betas] = ["structured-outputs-2025-11-13"]
      end

      # Gemini preparation
      sig { params(request_params: T::Hash[Symbol, T.untyped]).void }
      def prepare_gemini_request(request_params)
        begin
          require "dspy/gemini"
        rescue LoadError
          msg = <<~MSG
            Gemini adapter is optional; structured output helpers will be unavailable until the gem is installed.
            Add `gem 'dspy-gemini'` to your Gemfile and run `bundle install`.
          MSG
          raise DSPy::LM::MissingAdapterError, msg
        end

        # Check if structured outputs are supported
        if adapter.instance_variable_get(:@structured_outputs_enabled) && DSPy::Gemini::LM::SchemaConverter.supports_structured_outputs?(adapter.model)
          schema = DSPy::Gemini::LM::SchemaConverter.to_gemini_format(signature_class)

          request_params[:generation_config] = {
            response_mime_type: "application/json",
            response_json_schema: schema
          }
        end
      end

      # Extract JSON from content that may contain markdown or plain JSON
      sig { params(content: String).returns(String) }
      def extract_json_from_content(content)
        return content if content.nil? || content.empty?

        # Fix Anthropic Beta API bug with optional fields producing invalid JSON
        # When some output fields are optional and not returned, Anthropic's structured outputs
        # can produce trailing comma+brace: {"field1": {...},} instead of {"field1": {...}}
        # This workaround removes the invalid trailing syntax before JSON parsing
        if content =~ /,\s*\}\s*$/
          content = content.sub(/,(\s*\}\s*)$/, '\1')
        end

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
