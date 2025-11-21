# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/gepa/version"
require_relative "lib/gepa/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-gepa"
  spec.version = DSPy::GEPA::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "GEPA teleprompter integration for DSPy.rb."
  spec.description = "Ships DSPy::Teleprompt::GEPA plus reflective adapters, experiment tracking, and telemetry hooks built on top of the GEPA optimizer core gem."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/gepa.rb
    lib/dspy/gepa/**/*.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", ">= 0.30"
  spec.add_dependency "gepa", "= #{GEPA::VERSION}"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
