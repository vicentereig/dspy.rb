# frozen_string_literal: true

require 'dry-configurable'

module DSPy
  module Configuration
    # Configuration for OpenTelemetry subscriber
    class OtelConfig
      extend Dry::Configurable

      setting :tracer_name, default: 'dspy-ruby'
      setting :service_name, default: 'dspy-application'
      setting :service_version, default: DSPy::VERSION
      setting :endpoint, default: -> { ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] }
    end
  end
end