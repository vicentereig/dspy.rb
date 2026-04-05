# frozen_string_literal: true

require 'dspy/openai/version'
require 'dspy/support/openai_sdk_warning'

require 'dspy/openai/lm/adapters/openai_adapter'
require 'dspy/openai/lm/adapters/ollama_adapter'
require 'dspy/openai/lm/adapters/openrouter_adapter'
require 'dspy/openai/lm/schema_converter'

DSPy::Support::OpenAISDKWarning.warn_if_community_gem_loaded!
