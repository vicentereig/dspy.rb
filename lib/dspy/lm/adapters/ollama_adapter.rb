# frozen_string_literal: true

require 'openai'

module DSPy
  class LM
    class OllamaAdapter < OpenAIAdapter
      DEFAULT_BASE_URL = 'http://localhost:11434/v1'
      
      def initialize(model:, api_key: nil, base_url: nil, structured_outputs: true)
        # Ollama doesn't require API key for local instances
        # But may need it for remote/protected instances
        api_key ||= 'ollama' # OpenAI client requires non-empty key
        base_url ||= DEFAULT_BASE_URL
        
        # Store base_url before calling super
        @base_url = base_url
        
        # Don't call parent's initialize, do it manually to control client creation
        @model = model
        @api_key = api_key
        @structured_outputs_enabled = structured_outputs
        validate_configuration!
        
        # Create client with custom base URL
        @client = OpenAI::Client.new(
          api_key: @api_key,
          base_url: @base_url
        )
      end
      
      def chat(messages:, signature: nil, response_format: nil, &block)
        # For Ollama, we need to be more lenient with structured outputs
        # as it may not fully support OpenAI's response_format spec
        begin
          super
        rescue => e
          # If structured output fails, retry with enhanced prompting
          if @structured_outputs_enabled && signature && e.message.include?('response_format')
            DSPy.logger.debug("Ollama structured output failed, falling back to enhanced prompting")
            @structured_outputs_enabled = false
            retry
          else
            raise
          end
        end
      end
      
      private
      
      def validate_configuration!
        super
        # Additional Ollama-specific validation could go here
      end
      
      def validate_api_key!(api_key, provider)
        # For Ollama, API key is optional for local instances
        # Only validate if it looks like a remote URL
        if @base_url && !@base_url.include?('localhost') && !@base_url.include?('127.0.0.1')
          super
        end
      end
      
      
      # Ollama may have different model support for structured outputs
      def supports_structured_outputs?
        # For now, assume all Ollama models support basic JSON mode
        # but may not support full OpenAI structured output spec
        true
      end
    end
  end
end