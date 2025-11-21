# frozen_string_literal: true

require_relative "lib/dspy/version"
require_relative "lib/dspy/code_act/version"

Gem::Specification.new do |spec|
  spec.name = "dspy-code_act"
  spec.version = DSPy::CodeActVersion::VERSION
  spec.authors = ["Vicente Reig Rincón de Arellano"]
  spec.email = ["hey@vicente.services"]

  spec.summary = "Dynamic code generation agents for DSPy.rb."
  spec.description = "CodeAct provides Think-Code-Observe agents that synthesize and execute Ruby code dynamically. Ship DSPy.rb workflows that write custom Ruby code while tracking execution history, observations, and safety signals."
  spec.homepage = "https://github.com/vicentereig/dspy.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.files = Dir.glob(%w[
    lib/dspy/code_act.rb
    lib/dspy/code_act/**/*.rb
    lib/dspy/code_act/README.md
    README.md
    LICENSE
  ])

  spec.require_paths = ["lib"]

  spec.add_dependency "dspy", ">= 0.30"

  spec.metadata["github_repo"] = "git@github.com:vicentereig/dspy.rb"
end
