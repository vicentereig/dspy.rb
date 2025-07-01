# frozen_string_literal: true

require 'dry-configurable'

module DSPy
  module Configuration
    # Configuration for Langfuse subscriber
    class LangfuseConfig
      extend Dry::Configurable

      setting :public_key, default: -> { ENV['LANGFUSE_PUBLIC_KEY'] }
      setting :secret_key, default: -> { ENV['LANGFUSE_SECRET_KEY'] }
      setting :host, default: -> { ENV['LANGFUSE_HOST'] }
      setting :track_tokens, default: true
      setting :track_costs, default: true
      setting :track_prompts, default: true
    end
  end
end