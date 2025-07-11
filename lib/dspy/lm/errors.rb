# frozen_string_literal: true

module DSPy
  class LM
    class Error < StandardError; end
    class AdapterError < Error; end
    class UnsupportedProviderError < Error; end
    class ConfigurationError < Error; end
    
    # Raised when API key is missing or invalid
    class MissingAPIKeyError < Error
      def initialize(provider)
        env_var = case provider
                  when 'openai' then 'OPENAI_API_KEY'
                  when 'anthropic' then 'ANTHROPIC_API_KEY'
                  else "#{provider.upcase}_API_KEY"
                  end
        
        super("API key is required but was not provided. Set it via the api_key parameter or #{env_var} environment variable.")
      end
    end
  end
end
