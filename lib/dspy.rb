# frozen_string_literal: true
require 'ruby_llm'

module DSPy
  class << self
    attr_accessor :lm
    
    def configure(lm: nil)
      @lm = lm
    end
  end
end

require_relative 'dspy/field'
require_relative 'dspy/signature'
require_relative 'dspy/lm'
require_relative 'dspy/predict'
require_relative 'dspy/chain_of_thought' 