# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/gemini/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-gemini"
  spec.version = DSPy::Gemini::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Gemini adapters for DSPy.rb."
  spec.description = "Provides the GeminiAdapter so Gemini-compatible providers can be added to DSPy.rb projects independently of the core gem."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/gemini.rb
    lib/dspy/gemini/**/*.rb
    lib/dspy/gemini/README.md
    README.md
    LICENSE
  ]).uniq

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", "= #{DSPy::VERSION}"
  spec.add_dependency "gemini-ai", "~> 4.3"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
