# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/ruby_llm/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-ruby_llm"
  spec.version = DSPy::RubyLLM::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano", "Kieran Klaassen"]
  spec.email = ["hey@vicente.services", "kieranklaassen@gmail.com"]

  spec.summary = "RubyLLM adapter for DSPy.rb - unified access to 12+ LLM providers."
  spec.description = "Provides a unified adapter using RubyLLM to access OpenAI, Anthropic, Gemini, Bedrock, Ollama, and more through a single interface in DSPy.rb projects."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/ruby_llm.rb
    lib/dspy/ruby_llm/**/*.rb
    lib/dspy/ruby_llm/README.md
    README.md
    LICENSE
  ]).uniq

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", ">= 0.30"
  spec.add_dependency "ruby_llm", "~> 1.3"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
