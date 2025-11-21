# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/anthropic/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-anthropic"
  spec.version = DSPy::Anthropic::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Anthropic adapters for DSPy.rb."
  spec.description = "Provides the AnthropicAdapter so Claude-compatible providers can be added to DSPy.rb projects independently of the core gem."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/anthropic.rb
    lib/dspy/anthropic/**/*.rb
    README.md
    LICENSE
  ]).uniq

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", ">= 0.30"
  spec.add_dependency "anthropic"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
