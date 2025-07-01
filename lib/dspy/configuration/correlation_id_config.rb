# frozen_string_literal: true

require 'dry-configurable'
require 'securerandom'

module DSPy
  module Configuration
    # Configuration for correlation ID generation and handling
    class CorrelationIdConfig
      extend Dry::Configurable

      setting :enabled, default: false
      setting :header, default: 'X-Correlation-ID'
      setting :generator, default: -> { SecureRandom.uuid }
    end
  end
end