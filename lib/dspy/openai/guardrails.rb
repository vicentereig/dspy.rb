# frozen_string_literal: true

require 'dspy/lm/errors'

module DSPy
  module OpenAI
    class Guardrails
      SUPPORTED_OPENAI_VERSIONS = "~> 0.17".freeze

      def self.ensure_openai_installed!
        require 'openai'

        spec = Gem.loaded_specs["openai"] 
        unless spec && Gem::Requirement.new(SUPPORTED_OPENAI_VERSIONS).satisfied_by?(spec.version)
          msg = <<~MSG
            DSPY requires the official `openai` gem #{SUPPORTED_OPENAI_VERSIONS}.
            Please install or upgrade it with `bundle add openai --version "#{SUPPORTED_OPENAI_VERSIONS}"`.
          MSG
          raise DSPy::LM::UnsupportedVersionError, msg
        end

        if Gem.loaded_specs["ruby-openai"]
          msg = <<~MSG
            DSPy uses the official `openai` gem.
            Please remove the `ruby-openai` gem to avoid namespace conflicts.
          MSG
          raise DSPy::LM::MissingOfficialSDKError, msg
        end
      end
    end
  end
end
