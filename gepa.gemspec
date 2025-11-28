# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/gepa/version"

Gem::Specification.new do |spec|
  spec.name = "gepa"
  spec.version = GEPA::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Gradient-based Exploration and Pareto Agents for DSPy.rb."
  spec.description = "GEPA delivers optimization strategies, telemetry, and proposer tooling for reflective DSPy agents."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/gepa.rb
    lib/gepa/**/*.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", "< 1.0.0"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
