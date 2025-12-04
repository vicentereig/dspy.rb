# frozen_string_literal: true

require 'dspy/ruby_llm/version'

require 'dspy/ruby_llm/guardrails'
DSPy::RubyLLM::Guardrails.ensure_ruby_llm_installed!

require 'dspy/ruby_llm/lm/adapters/ruby_llm_adapter'
