# frozen_string_literal: true

require 'openai'

module DSPy
  class LM
    class OpenAIAdapter < Adapter
      def initialize(model:, api_key:)
        super
        @client = OpenAI::Client.new(api_key: api_key)
      end

      def chat(messages:, &block)
        request_params = {
          model: model,
          messages: normalize_messages(messages),
          temperature: 0.0 # DSPy default for deterministic responses
        }

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

          content = response.choices.first.message.content
          usage = response.usage

          Response.new(
            content: content,
            usage: usage.respond_to?(:to_h) ? usage.to_h : usage,
            metadata: {
              provider: 'openai',
              model: model,
              response_id: response.id,
              created: response.created
            }
          )
        rescue => e
          raise AdapterError, "OpenAI adapter error: #{e.message}"
        end
      end
    end
  end
end
