# frozen_string_literal: true

module DSPy
  class LM
    # Factory for creating appropriate adapters based on model_id
    class AdapterFactory
      # Maps provider prefixes to adapter classes
      ADAPTER_MAP = {
        'openai' => 'OpenAIAdapter',
        'anthropic' => 'AnthropicAdapter',
        'ollama' => 'OllamaAdapter',
        'gemini' => 'GeminiAdapter'
      }.freeze

      class << self
        # Creates an adapter instance based on model_id
        # @param model_id [String] Full model identifier (e.g., "openai/gpt-4")
        # @param api_key [String] API key for the provider
        # @param options [Hash] Additional adapter-specific options
        # @return [DSPy::LM::Adapter] Appropriate adapter instance
        def create(model_id, api_key:, **options)
          provider, model = parse_model_id(model_id)
          adapter_class = get_adapter_class(provider)
          
          # Pass provider-specific options
          adapter_options = { model: model, api_key: api_key }
          # OpenAI, Ollama, and Gemini accept additional options
          adapter_options.merge!(options) if %w[openai ollama gemini].include?(provider)
          
          adapter_class.new(**adapter_options)
        end

        private

        # Parse model_id to determine provider and model
        def parse_model_id(model_id)
          unless model_id.include?('/')
            raise ArgumentError, "model_id must include provider (e.g., 'openai/gpt-4', 'anthropic/claude-3'). Legacy format without provider is no longer supported."
          end
          
          provider, model = model_id.split('/', 2)
          [provider, model]
        end

        def get_adapter_class(provider)
          adapter_class_name = ADAPTER_MAP[provider]
          
          unless adapter_class_name
            available_providers = ADAPTER_MAP.keys.join(', ')
            raise UnsupportedProviderError, 
                  "Unsupported provider: #{provider}. Available: #{available_providers}"
          end

          begin
            Object.const_get("DSPy::LM::#{adapter_class_name}")
          rescue NameError
            raise UnsupportedProviderError, 
                  "Adapter not found: DSPy::LM::#{adapter_class_name}. " \
                  "Make sure the corresponding gem is installed."
          end
        end
      end
    end
  end
end
