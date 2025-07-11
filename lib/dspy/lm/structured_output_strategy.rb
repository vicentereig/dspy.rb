# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class LM
    # Enum for structured output strategies
    class StructuredOutputStrategy < T::Enum
      enums do
        OpenAIStructuredOutput = new("openai_structured_output")
        AnthropicExtraction = new("anthropic_extraction")
        EnhancedPrompting = new("enhanced_prompting")
      end
    end
  end
end