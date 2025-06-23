# frozen_string_literal: true

require 'anthropic'

module DSPy
  class LM
    class AnthropicAdapter < Adapter
      def initialize(model:, api_key:)
        super
        @client = Anthropic::Client.new(api_key: api_key)
      end

      def chat(messages:, &block)
        # Anthropic requires system message to be separate from messages
        system_message, user_messages = extract_system_message(normalize_messages(messages))
        
        request_params = {
          model: model,
          messages: user_messages,
          max_tokens: 4096, # Required for Anthropic
          temperature: 0.0 # DSPy default for deterministic responses
        }

        # Add system message if present
        request_params[:system] = system_message if system_message

        # Add streaming if block provided
        if block_given?
          request_params[:stream] = true
        end

        begin
          if block_given?
            content = ""
            @client.messages.stream(**request_params) do |chunk|
              if chunk.respond_to?(:delta) && chunk.delta.respond_to?(:text)
                chunk_text = chunk.delta.text
                content += chunk_text
                block.call(chunk)
              end
            end
            
            Response.new(
              content: content,
              usage: nil, # Usage not available in streaming
              metadata: {
                provider: 'anthropic',
                model: model,
                streaming: true
              }
            )
          else
            response = @client.messages.create(**request_params)
            
            if response.respond_to?(:error) && response.error
              raise AdapterError, "Anthropic API error: #{response.error}"
            end

            content = response.content.first.text if response.content.is_a?(Array) && response.content.first
            usage = response.usage

            Response.new(
              content: content,
              usage: usage.respond_to?(:to_h) ? usage.to_h : usage,
              metadata: {
                provider: 'anthropic',
                model: model,
                response_id: response.id,
                role: response.role
              }
            )
          end
        rescue => e
          raise AdapterError, "Anthropic adapter error: #{e.message}"
        end
      end

      private

      def extract_system_message(messages)
        system_message = nil
        user_messages = []

        messages.each do |msg|
          if msg[:role] == 'system'
            system_message = msg[:content]
          else
            user_messages << msg
          end
        end

        [system_message, user_messages]
      end
    end
  end
end
