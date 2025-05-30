# frozen_string_literal: true
require 'ruby_llm'
require 'dry-schema'
require 'dry-configurable'
require 'dry/logger'
require_relative 'dspy/ext/dry_schema'

module DSPy
  extend Dry::Configurable
  setting :lm
  setting :logger, default: Dry.Logger(:dspy, formatter: :string)

  def self.logger
    config.logger
  end
end

require_relative 'dspy/types'
require_relative 'dspy/module'
require_relative 'dspy/field'
require_relative 'dspy/signature'
require_relative 'dspy/lm'
require_relative 'dspy/predict'
require_relative 'dspy/chain_of_thought'
require_relative 'dspy/re_act'
require_relative 'dspy/tools'
