# frozen_string_literal: true

module DSPy
  class LM
    # Factory for creating appropriate adapters based on model_id
    class AdapterFactory
      # Maps provider prefixes to adapter classes
      ADAPTER_MAP = {
        'openai' => { class_name: 'DSPy::OpenAI::LM::Adapters::OpenAIAdapter', gem_name: 'dspy-openai' },
        'anthropic' => 'DSPy::LM::AnthropicAdapter',
        'ollama' => { class_name: 'DSPy::OpenAI::LM::Adapters::OllamaAdapter', gem_name: 'dspy-openai' },
        'gemini' => 'DSPy::LM::GeminiAdapter',
        'openrouter' => { class_name: 'DSPy::OpenAI::LM::Adapters::OpenRouterAdapter', gem_name: 'dspy-openai' }
      }.freeze

      PROVIDERS_WITH_EXTRA_OPTIONS = %w[openai anthropic ollama gemini openrouter].freeze

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
          # Some providers accept additional options
          adapter_options.merge!(options) if PROVIDERS_WITH_EXTRA_OPTIONS.include?(provider)
          
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
            Object.const_get(adapter_class_name)
          rescue NameError
            gem_name = ADAPTER_MAP[provider][:gem_name]
            raise UnsupportedProviderError,
                  "Adapter not found: #{adapter_class_name}. " \
                  "Make sure the corresponding #{gem_name} gem is installed."
          end
        end
      end
    end
  end
end
