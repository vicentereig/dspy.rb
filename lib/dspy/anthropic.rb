# frozen_string_literal: true

require 'dspy/anthropic/version'

require 'dspy/anthropic/guardrails'
DSPy::Anthropic::Guardrails.ensure_anthropic_installed!

require 'dspy/anthropic/lm/adapters/anthropic_adapter'
