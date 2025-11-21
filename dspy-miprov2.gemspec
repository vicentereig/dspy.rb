# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/miprov2/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-miprov2"
  spec.version = DSPy::MIPROv2::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "MIPROv2 optimizer and Bayesian tooling for DSPy.rb."
  spec.description = "Optional optimizer bundle for DSPy.rb that ships the MIPROv2 teleprompter, Gaussian Process backend, and supporting dependencies for Bayesian optimization."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/miprov2.rb
    lib/dspy/miprov2/**/*.rb
    lib/dspy/teleprompt/mipro_v2.rb
    lib/dspy/optimizers/gaussian_process.rb
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", ">= 0.30"
  spec.add_dependency "numo-narray-alt", "~> 0.9"
  spec.add_dependency "numo-tiny_linalg", "~> 0.4"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
