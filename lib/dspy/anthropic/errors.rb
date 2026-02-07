# frozen_string_literal: true

module DSPy
  module Anthropic
    # Raised when Anthropic blocks output due to content filtering/safety policies
    class ContentFilterError < DSPy::LM::AdapterError; end
  end
end
