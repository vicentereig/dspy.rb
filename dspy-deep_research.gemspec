# frozen_string_literal: true

require_relative "lib/dspy/deep_research/version"
require_relative "lib/dspy/deep_search/version"

Gem::Specification.new do |spec|
  spec.name          = "dspy-deep_research"
  spec.version       = DSPy::DeepResearch::VERSION
  spec.authors       = ["Vicente Reig Rincón de Arellano"]
  spec.email         = ["oss@vicente.services"]

  spec.summary       = "DeepResearch orchestration for DSPy"
  spec.description   = "Planner, queue, and coherence orchestration built on DSPy::DeepSearch."
  spec.homepage      = "https://vicentereig.github.io/dspy.rb/"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir.glob(%w[
    lib/dspy/deep_research.rb
    lib/dspy/deep_research/**/*.rb
    lib/dspy/deep_research/README.md
    lib/dspy/deep_search/**/*.rb
    README.md
    LICENSE
  ])
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/vicentereig/dspy.rb"
  spec.metadata["changelog_uri"] = "https://github.com/vicentereig/dspy.rb/blob/main/CHANGELOG.md"

  spec.add_dependency "dspy", "~> 0.30", ">= 0.30.1"
  spec.add_dependency "dspy-deep_search", "= #{DSPy::DeepSearch::VERSION}"
  spec.add_dependency "sorbet-runtime", "~> 0.5"
end
