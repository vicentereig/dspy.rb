# frozen_string_literal: true
require 'sorbet-runtime'
require 'dry-configurable'
require 'dry/logger'
require 'securerandom'

require_relative 'dspy/version'

module DSPy
  extend Dry::Configurable

  # Timestamp format options for instrumentation events
  class TimestampFormat < T::Enum
    enums do
      ISO8601 = new('iso8601')
      RFC3339_NANO = new('rfc3339_nano')
      UNIX_NANO = new('unix_nano')
    end
  end
  
  setting :lm
  setting :logger, default: Dry.Logger(:dspy, formatter: :string)
  
  # Nested instrumentation configuration using proper dry-configurable syntax
  setting :instrumentation do
    # Core settings
    setting :enabled, default: false
    setting :subscribers, default: []
    setting :sampling_rate, default: 1.0
    setting :trace_level, default: :standard
    setting :async_processing, default: false
    setting :buffer_size, default: 1000
    setting :flush_interval, default: 30
    setting :error_reporting, default: false
    setting :error_service, default: nil
    setting :sampling_rules, default: {}
    setting :timestamp_format, default: TimestampFormat::ISO8601

    # Nested correlation ID configuration
    setting :correlation_id do
      setting :enabled, default: false
      setting :header, default: 'X-Correlation-ID'
      setting :generator, default: -> { SecureRandom.uuid }
    end

    # Nested logger configuration
    setting :logger do
      setting :level, default: :info
      setting :include_payloads, default: true
      setting :correlation_id, default: true
      setting :sampling, default: {}
      setting :sampling_conditions, default: {}
    end

    # Nested OpenTelemetry configuration
    setting :otel do
      setting :tracer_name, default: 'dspy-ruby'
      setting :service_name, default: 'dspy-application'
      setting :service_version, default: DSPy::VERSION
      setting :endpoint, default: -> { ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] }
    end

    # Nested New Relic configuration
    setting :newrelic do
      setting :app_name, default: 'DSPy Application'
      setting :license_key, default: -> { ENV['NEW_RELIC_LICENSE_KEY'] }
      setting :custom_attributes, default: {}
    end

    # Nested Langfuse configuration
    setting :langfuse do
      setting :public_key, default: -> { ENV['LANGFUSE_PUBLIC_KEY'] }
      setting :secret_key, default: -> { ENV['LANGFUSE_SECRET_KEY'] }
      setting :host, default: -> { ENV['LANGFUSE_HOST'] }
      setting :track_tokens, default: true
      setting :track_costs, default: true
      setting :track_prompts, default: true
    end
  end

  def self.logger
    config.logger
  end

  # Validation methods for instrumentation configuration
  def self.validate_instrumentation!
    config = self.config.instrumentation
    
    raise ArgumentError, "Sampling rate must be between 0.0 and 1.0" unless config.sampling_rate.between?(0.0, 1.0)
    raise ArgumentError, "Buffer size must be positive" unless config.buffer_size > 0
    raise ArgumentError, "Flush interval must be positive" unless config.flush_interval > 0
    raise ArgumentError, "Invalid trace level" unless [:minimal, :standard, :detailed].include?(config.trace_level)
    raise ArgumentError, "Invalid timestamp format" unless config.timestamp_format.is_a?(TimestampFormat)
    
    if config.enabled && config.subscribers.empty?
      raise ArgumentError, "Must specify at least one subscriber when instrumentation is enabled"
    end
    
    # Validate subscribers are valid symbols
    invalid_subscribers = config.subscribers - [:logger, :otel, :newrelic, :langfuse]
    unless invalid_subscribers.empty?
      raise ArgumentError, "Invalid subscribers: #{invalid_subscribers.join(', ')}"
    end
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
require_relative 'dspy/teleprompt/teleprompter'
require_relative 'dspy/teleprompt/utils'
require_relative 'dspy/teleprompt/data_handler'
require_relative 'dspy/propose/grounded_proposer'
require_relative 'dspy/teleprompt/simple_optimizer'
require_relative 'dspy/teleprompt/mipro_v2'
require_relative 'dspy/subscribers/logger_subscriber'
require_relative 'dspy/tools'
require_relative 'dspy/instrumentation'
require_relative 'dspy/storage/program_storage'
require_relative 'dspy/storage/storage_manager'
require_relative 'dspy/registry/signature_registry'
require_relative 'dspy/registry/registry_manager'

# LoggerSubscriber will be lazy-initialized when first accessed
