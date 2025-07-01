# frozen_string_literal: true

require 'dry-configurable'

module DSPy
  module Configuration
    # Configuration class for DSPy instrumentation settings
    # Provides settings for enabling/disabling instrumentation, managing subscribers,
    # and configuring monitoring behavior
    class InstrumentationConfig
      extend Dry::Configurable

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

      # Nested configurations
      setting :correlation_id, default: DSPy::Configuration::CorrelationIdConfig
      setting :logger, default: DSPy::Configuration::LoggerConfig  
      setting :otel, default: DSPy::Configuration::OtelConfig
      setting :newrelic, default: DSPy::Configuration::NewRelicConfig
      setting :langfuse, default: DSPy::Configuration::LangfuseConfig
      setting :sampling_rules, default: {}

      # Validate settings after configuration
      def self.validate!
        config = self.config
        
        raise ArgumentError, "Sampling rate must be between 0.0 and 1.0" unless config.sampling_rate.between?(0.0, 1.0)
        raise ArgumentError, "Buffer size must be positive" unless config.buffer_size > 0
        raise ArgumentError, "Flush interval must be positive" unless config.flush_interval > 0
        raise ArgumentError, "Invalid trace level" unless [:minimal, :standard, :detailed].include?(config.trace_level)
        
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
  end
end