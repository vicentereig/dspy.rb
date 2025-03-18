# frozen_string_literal: true
require 'ruby_llm'
require 'dry-schema'
require 'dry-configurable'
require_relative 'dspy/ext/dry_schema'

module DSPy
  extend Dry::Configurable
  setting :lm
end

require_relative 'dspy/types'
require_relative 'dspy/module'
require_relative 'dspy/field' # gonna begone
require_relative 'dspy/signature'
require_relative 'dspy/lm'
require_relative 'dspy/predict'
require_relative 'dspy/chain_of_thought'

