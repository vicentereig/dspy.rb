# frozen_string_literal: true

require 'dry-configurable'

module DSPy
  module Configuration
    # Configuration for logger subscriber behavior
    class LoggerConfig
      extend Dry::Configurable

      setting :level, default: :info
      setting :include_payloads, default: true
      setting :correlation_id, default: true
      setting :sampling, default: {}
      setting :sampling_conditions, default: {}
    end
  end
end