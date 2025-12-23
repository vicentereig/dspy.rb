# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/o11y/version"
require_relative "lib/dspy/o11y/langfuse/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-o11y-langfuse"
  spec.version = DSPy::O11y::Langfuse::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Langfuse auto-configuration adapter for DSPy observability."
  spec.description = "Registers the Langfuse OpenTelemetry exporter with DSPy::Observability so spans flow to Langfuse when the required environment variables are present."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/o11y/langfuse.rb
    lib/dspy/o11y/langfuse/version.rb
    lib/dspy/o11y/langfuse/scores_exporter.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy-o11y", ">= 0.30"
  spec.add_dependency "opentelemetry-sdk", "~> 1.8"
  spec.add_dependency "opentelemetry-exporter-otlp", "~> 0.30"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
