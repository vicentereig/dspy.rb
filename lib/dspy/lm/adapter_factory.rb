# frozen_string_literal: true

module DSPy
  class LM
    # Factory for creating appropriate adapters based on model_id
    class AdapterFactory
      # Maps provider prefixes to adapter classes
      ADAPTER_MAP = {
        'openai' => 'OpenAIAdapter',
        'anthropic' => 'AnthropicAdapter',
        'ruby_llm' => 'RubyLLMAdapter'
      }.freeze

      class << self
        # Creates an adapter instance based on model_id
        # @param model_id [String] Full model identifier (e.g., "openai/gpt-4")
        # @param api_key [String] API key for the provider
        # @return [DSPy::LM::Adapter] Appropriate adapter instance
        def create(model_id, api_key:)
          provider, model = parse_model_id(model_id)
          adapter_class = get_adapter_class(provider)
          
          adapter_class.new(model: model, api_key: api_key)
        end

        private

        # Parse model_id to determine provider and model
        def parse_model_id(model_id)
          if model_id.include?('/')
            provider, model = model_id.split('/', 2)
            [provider, model]
          else
            # Legacy format: assume ruby_llm for backward compatibility
            ['ruby_llm', model_id]
          end
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
