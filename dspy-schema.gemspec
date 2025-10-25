# frozen_string_literal: true

require_relative "lib/dspy/schema/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-schema"
  spec.version = DSPy::Schema::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Sorbet to JSON Schema conversion utilities reused by DSPy.rb."
  spec.description = "Provides DSPy::TypeSystem::SorbetJsonSchema without requiring the full DSPy stack, enabling reuse in sibling gems and downstream projects."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/schema.rb
    lib/dspy/schema/**/*.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "sorbet-runtime", ">= 0.5.0"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
