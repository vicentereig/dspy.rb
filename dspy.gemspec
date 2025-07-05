# frozen_string_literal: true

require_relative "lib/dspy/version"

Gem::Specification.new do |spec|
  spec.name = "dspy"
  spec.version = DSPy::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Ruby port of DSPy 2.6"
  spec.description = "A Ruby implementation of DSPy, a framework for programming with large language models"
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[lib/**/*.rb README.md LICENSE.txt])

  # Uncomment to register executables
  # spec.bindir = "exe"
  # spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "dry-configurable", "~> 1.0"
  spec.add_dependency "dry-logger", "~> 1.0"
  spec.add_dependency "dry-monitor", "~> 1.0"
  spec.add_dependency "async", "~> 2.23"

  # Official LM provider clients
  spec.add_dependency "openai", "~> 0.9.0"
  spec.add_dependency "anthropic", "~> 1.1.0"

  # Sorbet integration dependencies
  spec.add_dependency "sorbet-runtime", "~> 0.5"
  spec.add_dependency "sorbet-schema", "~> 0.3"

  # Data processing
  spec.add_dependency "polars-df", "~> 0.20.0"

  # Local embeddings
  spec.add_dependency "informers", "~> 1.2"

  # Development dependencies are already specified in the Gemfile
end
