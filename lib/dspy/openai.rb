# frozen_string_literal: true

require 'dspy/openai/version'

require 'dspy/openai/guardrails'
DSPy::OpenAI::Guardrails.ensure_openai_installed!

require 'dspy/openai/lm/adapters/openai_adapter'
require 'dspy/openai/lm/adapters/ollama_adapter'
require 'dspy/openai/lm/adapters/openrouter_adapter'
require 'dspy/openai/lm/schema_converter'
