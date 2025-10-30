# frozen_string_literal: true

require 'dspy/lm/errors'

module DSPy
  module Gemini
    class Guardrails
      SUPPORTED_GEMINI_VERSIONS = "~> 4.3".freeze

      def self.ensure_gemini_installed!
        require 'gemini-ai'

        spec = Gem.loaded_specs["gemini-ai"]
        unless spec && Gem::Requirement.new(SUPPORTED_GEMINI_VERSIONS).satisfied_by?(spec.version)
          msg = <<~MSG
            DSPY requires `gemini-ai` gem #{SUPPORTED_GEMINI_VERSIONS}.
            Please Install or upgrade it with `bundle add gemini-ai --version "#{SUPPORTED_GEMINI_VERSIONS}"`.
          MSG
          raise DSPy::LM::UnsupportedVersionError, msg
        end
      end
    end
  end
end

