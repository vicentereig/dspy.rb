# frozen_string_literal: true

require 'dspy/lm/errors'

module DSPy
  module RubyLLM
    class Guardrails
      SUPPORTED_RUBY_LLM_VERSIONS = "~> 1.3".freeze

      def self.ensure_ruby_llm_installed!
        require 'ruby_llm'

        spec = Gem.loaded_specs["ruby_llm"]
        unless spec && Gem::Requirement.new(SUPPORTED_RUBY_LLM_VERSIONS).satisfied_by?(spec.version)
          msg = <<~MSG
            DSPy requires the `ruby_llm` gem #{SUPPORTED_RUBY_LLM_VERSIONS}.
            Please install or upgrade it with `bundle add ruby_llm --version "#{SUPPORTED_RUBY_LLM_VERSIONS}"`.
          MSG
          raise DSPy::LM::UnsupportedVersionError, msg
        end
      end
    end
  end
end
