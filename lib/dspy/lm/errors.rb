# frozen_string_literal: true

module DSPy
  class LM
    class Error < StandardError; end
    class AdapterError < Error; end
    class UnsupportedProviderError < Error; end
    class ConfigurationError < Error; end
  end
end
