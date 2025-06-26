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

  # Convenient instrumentation configuration
  def self.configure_instrumentation(&block)
    require_relative 'dspy/instrumentation'
    require_relative 'dspy/instrumentation/dry_monitor_bridge'
    
    Instrumentation.configure(&block)
    
    # Setup dry-monitor bridge for HTTP instrumentation
    if Instrumentation.config.enabled
      Instrumentation::DryMonitorBridge.setup!
      
      # Auto-enable logger subscriber for event-based logging
      require_relative 'dspy/subscribers/logger_subscriber'
      @logger_subscriber ||= Subscribers::LoggerSubscriber.new
    end
  end
end

require_relative 'dspy/module'
require_relative 'dspy/field'
require_relative 'dspy/signature'
require_relative 'dspy/lm'
require_relative 'dspy/predict'
require_relative 'dspy/chain_of_thought'
require_relative 'dspy/re_act'
require_relative 'dspy/subscribers/logger_subscriber'
require_relative 'dspy/tools'
