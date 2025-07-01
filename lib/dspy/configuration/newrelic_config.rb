# frozen_string_literal: true

require 'dry-configurable'

module DSPy
  module Configuration
    # Configuration for New Relic subscriber
    class NewRelicConfig
      extend Dry::Configurable

      setting :app_name, default: 'DSPy Application'
      setting :license_key, default: -> { ENV['NEW_RELIC_LICENSE_KEY'] }
      setting :custom_attributes, default: {}
    end
  end
end