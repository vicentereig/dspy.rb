# frozen_string_literal: true

module DSPy
  class Error < StandardError; end
  
  class ValidationError < Error; end
  
  class DeserializationError < Error; end
  
  class UnsupportedSchemaError < Error; end
  
  class ConfigurationError < Error
    def self.missing_lm(module_name)
      new(<<~MESSAGE)
        No language model configured for #{module_name} module.

        To fix this, configure a language model either globally:

          DSPy.configure do |config|
            config.lm = DSPy::LM.new("openai/gpt-4", api_key: ENV["OPENAI_API_KEY"])
          end

        Or on the module instance:

          module_instance.configure do |config|
            config.lm = DSPy::LM.new("anthropic/claude-3", api_key: ENV["ANTHROPIC_API_KEY"])
          end
      MESSAGE
    end
  end
end