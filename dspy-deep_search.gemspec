# frozen_string_literal: true

require_relative "lib/dspy/deep_search/version"

Gem::Specification.new do |spec|
  spec.name          = "dspy-deep_search"
  spec.version       = DSPy::DeepSearch::VERSION
  spec.authors       = ["Vicente Reig Rincón de Arellano"]
  spec.email         = ["oss@vicente.services"]

  spec.summary       = "DeepSearch primitives for DSPy"
  spec.description   = "DeepSearch loop utilities and modules for DSPy agents."
  spec.homepage      = "https://github.com/vicentereig/dspy.rb"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir.glob(%w[
    lib/dspy/deep_search.rb
    lib/dspy/deep_search/**/*.rb
    lib/dspy/deep_search/README.md
    README.md
    LICENSE
  ])
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.add_dependency "dspy", ">= 0.27.0"
  spec.add_dependency "exa-ai-ruby", ">= 1.0.0"
  spec.add_dependency "sorbet-runtime", ">= 0.5"
end
