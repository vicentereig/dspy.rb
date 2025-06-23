# frozen_string_literal: true

begin
  require 'ruby_llm'
rescue LoadError
  # ruby_llm is optional for backward compatibility
end

module DSPy
  class LM
    class RubyLLMAdapter < Adapter
      def initialize(model:, api_key:)
        super
        
        unless defined?(RubyLLM)
          raise ConfigurationError, 
                "ruby_llm gem is required for RubyLLMAdapter. " \
                "Add 'gem \"ruby_llm\"' to your Gemfile."
        end

        configure_ruby_llm
      end

      def chat(messages:, &block)
        begin
          chat = RubyLLM.chat(model: model)
          
          # Add messages to chat
          messages.each do |msg|
            chat.add_message(role: msg[:role].to_sym, content: msg[:content])
          end

          # Get the last user message for ask method
          last_user_message = messages.reverse.find { |msg| msg[:role] == 'user' }
          
          if last_user_message
            # Remove the last user message since ask() will add it
            chat.messages.pop if chat.messages.last&.content == last_user_message[:content]
            chat.ask(last_user_message[:content], &block)
          else
            raise AdapterError, "No user message found in conversation"
          end

          content = chat.messages.last&.content || ""

          Response.new(
            content: content,
            usage: nil, # ruby_llm doesn't provide usage info
            metadata: {
              provider: 'ruby_llm',
              model: model,
              message_count: chat.messages.length
            }
          )
        rescue => e
          raise AdapterError, "RubyLLM adapter error: #{e.message}"
        end
      end

      private

      def configure_ruby_llm
        # Determine provider from model for configuration
        if model.include?('gpt') || model.include?('openai')
          RubyLLM.configure do |config|
            config.openai_api_key = api_key
          end
        elsif model.include?('claude') || model.include?('anthropic')
          RubyLLM.configure do |config|
            config.anthropic_api_key = api_key
          end
        else
          # Default to OpenAI configuration
          RubyLLM.configure do |config|
            config.openai_api_key = api_key
          end
        end
      end
    end
  end
end
