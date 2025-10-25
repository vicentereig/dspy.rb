# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/o11y/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-o11y"
  spec.version = DSPy::O11y::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Observability core (spans, context hooks, and telemetry helpers) for DSPy.rb."
  spec.description = "Provides DSPy::Observability, AsyncSpanProcessor, and ObservationType so instrumentation can be enabled independently from the main DSPy gem."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/o11y.rb
    lib/dspy/o11y/**/*.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", "= #{DSPy::VERSION}"
  spec.add_dependency "concurrent-ruby", "~> 1.3"
  spec.add_dependency "opentelemetry-sdk", "~> 1.8"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
