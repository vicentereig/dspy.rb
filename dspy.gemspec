# frozen_string_literal: true

require_relative "lib/dspy/version"

Gem::Specification.new do |spec|
  spec.name = "dspy"
  spec.version = DSPy::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "The Ruby framework for programming—rather than prompting—language models."
  spec.description = "The Ruby framework for programming with large language models. DSPy.rb brings structured LLM programming to Ruby developers. Instead of wrestling with prompt strings and parsing responses, you define typed signatures using idiomatic Ruby to compose and decompose AI Worklows and AI Agents."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir[
    "lib/dspy.rb",
    "lib/dspy/**/*.rb",
    "README.md",
    "LICENSE"
  ].uniq

  spec.files.reject! { |path| path.start_with?("lib/dspy/datasets") }
  spec.files.reject! { |path| path.start_with?("lib/dspy/miprov2") }
  spec.files.reject! { |path| path == "lib/dspy/miprov2.rb" }
  spec.files.reject! { |path| path.start_with?("lib/dspy/teleprompt/mipro_v2") }
  spec.files.reject! { |path| path.start_with?("lib/dspy/optimizers/gaussian_process") }
  spec.files.reject! { |path| path.start_with?("lib/gepa") || path == "lib/gepa.rb" }

  # Uncomment to register executables
  # spec.bindir = "exe"
  # spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "dry-configurable", "~> 1.0"
  spec.add_dependency "dry-logger", "~> 1.0"
  spec.add_dependency "async", "~> 2.29"
  spec.add_dependency "concurrent-ruby", "~> 1.3"

  # Official LM provider clients
  spec.add_dependency "openai", "~> 0.22.0"
  spec.add_dependency "anthropic", "~> 1.5.0"
  spec.add_dependency "gemini-ai", "~> 4.3"

  # Sorbet integration dependencies
  spec.add_dependency "sorbet-runtime", "~> 0.5"
  spec.add_dependency "sorbet-schema", "~> 0.3"
  spec.add_dependency "sorbet-baml", "~> 0.1"

  # Local embeddings
  spec.add_dependency "informers", "~> 1.2"

  # Optional OpenTelemetry integration for Langfuse
  spec.add_dependency "opentelemetry-sdk", "~> 1.8"
  spec.add_dependency "opentelemetry-exporter-otlp", "~> 0.30"

  # Development dependencies are already specified in the Gemfile
end
