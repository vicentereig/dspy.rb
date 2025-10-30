# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/openai/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-openai"
  spec.version = DSPy::OpenAI::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "OpenAI and OpenRouter adapters for DSPy.rb."
  spec.description = "Provides the OpenAI plus the Ollama and OpenRouter adapters so OpenAI-compatible providers can be added to DSPy.rb projects independently of the core gem."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/openai.rb
    lib/dspy/openai/**/*.rb
    lib/dspy/openai/README.md
    README.md
    LICENSE
  ]).uniq

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", "= #{DSPy::VERSION}"
  spec.add_dependency "openai", "~> 0.34"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
