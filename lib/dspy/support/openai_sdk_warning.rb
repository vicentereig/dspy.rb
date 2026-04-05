# frozen_string_literal: true

module DSPy
  module Support
    module OpenAISDKWarning
      WARNING_MESSAGE = <<~WARNING.freeze
        WARNING: ruby-openai gem detected. This may cause conflicts with DSPy's OpenAI integration.

        DSPy uses the official 'openai' gem. The community 'ruby-openai' gem uses the same
        OpenAI namespace and will cause conflicts.

        To fix this, remove 'ruby-openai' from your Gemfile and use the official gem instead:
        - Remove: gem 'ruby-openai'
        - Keep: gem 'openai' (official SDK that DSPy uses)

        The official gem provides better compatibility and is actively maintained by OpenAI.
      WARNING

      def self.warn_if_community_gem_loaded!
        return if @warned
        return unless community_gem_loaded?

        Kernel.warn WARNING_MESSAGE
        @warned = true
      end

      def self.community_gem_loaded?
        defined?(::OpenAI) && defined?(::OpenAI::Client) && !defined?(::OpenAI::Internal)
      end
    end
  end
end
