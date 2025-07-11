# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  # User-facing enum for structured output strategy preferences
  class Strategy < T::Enum
    enums do
      # Use provider-optimized strategies when available (OpenAI structured outputs, Anthropic extraction)
      # Falls back to Compatible if provider-specific strategy isn't available
      Strict = new("strict")
      
      # Use enhanced prompting that works with any provider
      # More compatible but potentially less reliable than provider-specific strategies
      Compatible = new("compatible")
    end
  end
end