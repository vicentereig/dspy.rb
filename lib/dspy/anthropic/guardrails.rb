# frozen_string_literal: true

require 'dspy/lm/errors'

module DSPy
  module Anthropic
    class Guardrails
      SUPPORTED_ANTHROPIC_VERSIONS = "~> 1.12".freeze

      def self.ensure_anthropic_installed!
        require 'anthropic'

        spec = Gem.loaded_specs["anthropic"]
        unless spec && Gem::Requirement.new(SUPPORTED_ANTHROPIC_VERSIONS).satisfied_by?(spec.version)
          msg = <<~MSG
            DSPY requires the `anthropic` gem #{SUPPORTED_ANTHROPIC_VERSIONS}.
            Please install or upgrade it with `bundle add anthropic --version "#{SUPPORTED_ANTHROPIC_VERSIONS}"`.
          MSG
          raise DSPy::LM::UnsupportedVersionError, msg
        end
      end
    end
  end
end
