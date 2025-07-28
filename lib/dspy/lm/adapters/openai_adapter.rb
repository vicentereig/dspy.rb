# frozen_string_literal: true

require 'openai'
require_relative 'openai/schema_converter'

module DSPy
  class LM
    class OpenAIAdapter < Adapter
      def initialize(model:, api_key:, structured_outputs: false)
        super(model: model, api_key: api_key)
        validate_api_key!(api_key, 'openai')
        @client = OpenAI::Client.new(api_key: api_key)
        @structured_outputs_enabled = structured_outputs
      end

      def chat(messages:, signature: nil, response_format: nil, &block)
        request_params = {
          model: model,
          messages: normalize_messages(messages),
          temperature: 0.0 # DSPy default for deterministic responses
        }

        # Add response format if provided by strategy
        if response_format
          request_params[:response_format] = response_format
        elsif @structured_outputs_enabled && signature && supports_structured_outputs?
          # Legacy behavior for backward compatibility
          response_format = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(signature)
          request_params[:response_format] = response_format
        end

        # Add streaming if block provided
        if block_given?
          request_params[:stream] = proc do |chunk, _bytesize|
            block.call(chunk) if chunk.dig("choices", 0, "delta", "content")
          end
        end

        begin
          response = @client.chat.completions.create(**request_params)
          
          if response.respond_to?(:error) && response.error
            raise AdapterError, "OpenAI API error: #{response.error}"
          end

          choice = response.choices.first
          message = choice.message
          content = message.content
          usage = response.usage

          # Handle structured output refusals
          if message.respond_to?(:refusal) && message.refusal
            raise AdapterError, "OpenAI refused to generate output: #{message.refusal}"
          end

          # Convert usage data to typed struct
          usage_struct = UsageFactory.create('openai', usage)
          
          # Create typed metadata
          metadata = ResponseMetadataFactory.create('openai', {
            model: model,
            response_id: response.id,
            created: response.created,
            structured_output: @structured_outputs_enabled && signature && supports_structured_outputs?,
            system_fingerprint: response.system_fingerprint,
            finish_reason: choice.finish_reason
          })
          
          Response.new(
            content: content,
            usage: usage_struct,
            metadata: metadata
          )
        rescue => e
          raise AdapterError, "OpenAI adapter error: #{e.message}"
        end
      end

      private

      def supports_structured_outputs?
        DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?(model)
      end
    end
  end
end
