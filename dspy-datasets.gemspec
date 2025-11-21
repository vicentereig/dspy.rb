# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/datasets/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-datasets"
  spec.version = DSPy::Datasets::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Curated datasets and loaders for DSPy.rb."
  spec.description = "DSPy datasets provide prebuilt loaders, caching, and schema metadata for benchmark corpora used in DSPy examples and teleprompters."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/datasets.rb
    lib/dspy/datasets/**/*.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", ">= 0.30"
  spec.add_dependency "red-parquet", "~> 21.0"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
