# frozen_string_literal: true
require 'sorbet-runtime'
require 'dry-configurable'
require 'dry/logger'

module DSPy
  extend Dry::Configurable
  setting :lm
  setting :logger, default: Dry.Logger(:dspy, formatter: :string)

  def self.logger
    config.logger
  end
end

require_relative 'dspy/module'
require_relative 'dspy/field'
require_relative 'dspy/signature'
require_relative 'dspy/few_shot_example'
require_relative 'dspy/prompt'
require_relative 'dspy/example'
require_relative 'dspy/lm'
require_relative 'dspy/predict'
require_relative 'dspy/chain_of_thought'
require_relative 'dspy/re_act'
require_relative 'dspy/evaluate'
require_relative 'dspy/subscribers/logger_subscriber'
require_relative 'dspy/tools'
require_relative 'dspy/instrumentation'

# LoggerSubscriber will be lazy-initialized when first accessed
