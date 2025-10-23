# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/evals/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-evals"
  spec.version = DSPy::Evals::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Evaluation utilities for DSPy.rb programs."
  spec.description = "Provides the DSPy::Evals runtime, concurrency, callbacks, and export helpers for benchmarking Ruby DSPy programs."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/evals.rb
    lib/dspy/evals/**/*.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", "= #{DSPy::VERSION}"
  spec.add_dependency "concurrent-ruby", "~> 1.3"
  spec.add_dependency "polars-df", "~> 0.15"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
