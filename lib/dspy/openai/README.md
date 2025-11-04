# DSPy OpenAI adapter gem

`dspy-openai` packages the OpenAI-compatible adapters for DSPy.rb so we can keep the core `dspy` gem lean while still talking to GPT models (and any OpenAI-compatible endpoint). Install it whenever your project needs to invoke `openai/*`, `openrouter/*`, or `ollama/*` models through DSPy.

## When you need it
- You call `DSPy::LM.new` with a model id that starts with `openai/`, `openrouter/`, or `ollama/`.
- You want to take advantage of structured outputs, streaming, or multimodal (vision) features exposed by OpenAI's API.

If your project only uses non-OpenAI providers (e.g. Anthropic or Gemini) you can omit this gem entirely.

## Installation
Add the gem next to your `dspy` dependency and install Bundler dependencies:

```ruby
# Gemfile
gem 'dspy'
gem 'dspy-openai'
```

```sh
bundle install
```

The gem depends on the official `openai` Ruby SDK (`~> 0.17`). The adapter checks this at load time and will raise if an incompatible version, or the older `ruby-openai` gem, is detected.

## Basic usage

```ruby
require 'dspy'
# No need to explicitly require 'dspy/openai'

lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV.fetch('OPENAI_API_KEY'))

```

## Working with alternate providers
- **OpenRouter**: instantiate with `DSPy::LM.new('openrouter/x-ai/grok-4-fast:free', api_key: ENV['OPENROUTER_API_KEY'])`. Any OpenAI-compatible model exposed by OpenRouter will work.
- **Ollama**: use `DSPy::LM.new('ollama/llama3.2', api_key: nil)`.

All three adapters share the same request handling, structured output support, and error reporting, so you can swap providers without changing higher-level DSPy code.
