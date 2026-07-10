# frozen_string_literal: true

module DSPy
  class LM
    # Factory for creating appropriate adapters based on model_id
    class AdapterFactory
      # Maps provider prefixes to adapter classes
      ADAPTER_MAP = {
        'openai' => { class_name: 'DSPy::OpenAI::LM::Adapters::OpenAIAdapter', gem_name: 'dspy-openai' },
        'anthropic' => { class_name: 'DSPy::Anthropic::LM::Adapters::AnthropicAdapter', gem_name: 'dspy-anthropic' },
        'ollama' => { class_name: 'DSPy::OpenAI::LM::Adapters::OllamaAdapter', gem_name: 'dspy-openai' },
        'gemini' => { class_name: 'DSPy::Gemini::LM::Adapters::GeminiAdapter', gem_name: 'dspy-gemini' },
        'openrouter' => { class_name: 'DSPy::OpenAI::LM::Adapters::OpenRouterAdapter', gem_name: 'dspy-openai' },
        'ruby_llm' => { class_name: 'DSPy::RubyLLM::LM::Adapters::RubyLLMAdapter', gem_name: 'dspy-ruby_llm' }
      }.freeze

      PROVIDERS_WITH_EXTRA_OPTIONS = %w[openai anthropic ollama gemini openrouter ruby_llm].freeze

      # `reasoning:` is currently implemented only for the Anthropic adapter
      # (see adr/019-anthropic-reasoning-temperature-config.md). Checked here,
      # once, so every provider fails the same way instead of each adapter
      # either raising a raw ArgumentError (no `reasoning:` keyword declared)
      # or silently ignoring it (RubyLLMAdapter's `**options`).
      REASONING_SUPPORTED_PROVIDERS = %w[anthropic].freeze

      class AdapterData < Data.define(:class_name, :gem_name)
        def self.from_prefix(provider_prefix)
          if ADAPTER_MAP.key?(provider_prefix)
            new(**ADAPTER_MAP[provider_prefix])
          end
        end

        def require_path
          gem_name.tr('-', '/')
        end
      end

      class << self
        # Creates an adapter instance based on model_id
        # @param model_id [String] Full model identifier (e.g., "openai/gpt-4")
        # @param api_key [String] API key for the provider
        # @param options [Hash] Additional adapter-specific options
        # @return [DSPy::LM::Adapter] Appropriate adapter instance
        def create(model_id, api_key:, **options)
          provider, model = parse_model_id(model_id)
          adapter_class = get_adapter_class(provider)
          ensure_reasoning_supported!(provider, options)

          # Pass provider-specific options
          adapter_options = { model: model, api_key: api_key }
          # Some providers accept additional options
          adapter_options.merge!(options) if PROVIDERS_WITH_EXTRA_OPTIONS.include?(provider)
          
          adapter_class.new(**adapter_options)
        end

        private

        def ensure_reasoning_supported!(provider, options)
          return unless options.key?(:reasoning) && !options[:reasoning].nil?
          return if REASONING_SUPPORTED_PROVIDERS.include?(provider)

          raise DSPy::LM::ConfigurationError,
            "reasoning: is currently supported only by the Anthropic adapter " \
            "(got provider: #{provider.inspect}). See adr/019-anthropic-reasoning-temperature-config.md."
        end

        # Parse model_id to determine provider and model
        def parse_model_id(model_id)
          unless model_id.include?('/')
            raise ArgumentError, "model_id must include provider (e.g., 'openai/gpt-4', 'anthropic/claude-3'). Legacy format without provider is no longer supported."
          end
          
          provider, model = model_id.split('/', 2)
          [provider, model]
        end

        def get_adapter_class(provider)
          ensure_adapter_supported!(provider)
          ensure_adapter_loaded!(provider)

          Object.const_get(adapter_data(provider).class_name)
        end

        def adapter_data(provider)
          AdapterData.from_prefix(provider)
        end

        def ensure_adapter_supported!(provider)
          if adapter_data(provider).nil?
            available_providers = ADAPTER_MAP.keys.join(', ')
            raise UnsupportedProviderError, "Unsupported provider: #{provider}. Available: #{available_providers}"
          end
        end

        def ensure_adapter_loaded!(provider)
          adapter_data = adapter_data(provider)
          msg = <<~ERROR
            Adapter not found: #{adapter_data.class_name}.
            Install the #{adapter_data.gem_name} gem and try again.
          ERROR
          require adapter_data.require_path
        rescue LoadError
          raise MissingAdapterError, msg
        end
      end
    end
  end
end
