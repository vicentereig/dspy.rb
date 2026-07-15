---
layout: docs
name: Installation
description: Choose DSPy.rb packages and configure a provider
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
# Installation & Provider Setup

Choose and configure a provider here. To build and run a first program with OpenAI, follow the [Quick Start](/dspy.rb/getting-started/quick-start/).

## Requirements

DSPy.rb requires Ruby 3.3 or newer and Bundler.

## Install Core and an Adapter

Every application needs the core gem plus a provider adapter. For OpenAI, OpenRouter, or Ollama:

```ruby
# Gemfile
gem 'dspy'
gem 'dspy-openai'
```

Install the bundle:

```bash
bundle install
```

Installing only `dspy` does not install an OpenAI SDK or adapter. If code configures an `openai/*`, `openrouter/*`, or `ollama/*` model without `dspy-openai`, `DSPy::LM` raises `DSPy::LM::MissingAdapterError`.

The [package and capability matrix](/dspy.rb/getting-started/packages/) lists every package's status, exact require path, dependencies, and limitations. Provider and model capabilities still vary after a package is installed.

## Choose a Provider Adapter {#provider-setup}

| Model prefix | Gem | Credential |
| --- | --- | --- |
| `openai/*` | `dspy-openai` | `OPENAI_API_KEY` |
| `openrouter/*` | `dspy-openai` | `OPENROUTER_API_KEY` |
| `ollama/*` | `dspy-openai` | None for a default local server |
| `anthropic/*` | `dspy-anthropic` | `ANTHROPIC_API_KEY` |
| `gemini/*` | `dspy-gemini` | `GEMINI_API_KEY` |
| `ruby_llm/*` | `dspy-ruby_llm` | Depends on the routed provider and RubyLLM configuration |

`DSPy::LM` auto-requires the installed adapter from the model prefix. The prefix selects an adapter; it does not prove that a particular model supports schemas, tools, media, documents, or streaming. Check the package matrix and provider documentation for the selected model and SDK version.

## Configure Credentials

Set provider credentials in the process environment, for example:

```bash
export OPENAI_API_KEY=sk-your-key-here
export ANTHROPIC_API_KEY=sk-ant-your-key-here
export GEMINI_API_KEY=your-gemini-key
export OPENROUTER_API_KEY=sk-or-your-key-here
```

DSPy.rb reads only the value your application passes to `api_key:`. It does not load `.env` files. Load a `.env` file explicitly with an application dependency such as `dotenv`, or export variables in the shell or deployment environment.

Prefer `ENV.fetch` when a key is required:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV.fetch('OPENAI_API_KEY')
  )
end
```

With this form, a missing variable raises Ruby's `KeyError` before LM initialization. If an application passes `nil`, an empty string, or whitespace with `ENV['OPENAI_API_KEY']`, the OpenAI adapter raises `DSPy::LM::MissingAPIKeyError`.

## Configure a Provider

### OpenAI

```ruby
gem 'dspy'
gem 'dspy-openai'
```

Use an `openai/*` model identifier and pass `OPENAI_API_KEY`. Native structured-output support depends on the selected model; enable it only when the model and SDK support it:

```ruby
DSPy::LM.new(
  'openai/gpt-4o-mini',
  api_key: ENV.fetch('OPENAI_API_KEY'),
  structured_outputs: true
)
```

### Anthropic

```ruby
gem 'dspy'
gem 'dspy-anthropic'
```

```ruby
DSPy::LM.new(
  'anthropic/claude-sonnet-4-20250514',
  api_key: ENV.fetch('ANTHROPIC_API_KEY')
)
```

### Gemini

```ruby
gem 'dspy'
gem 'dspy-gemini'
```

```ruby
DSPy::LM.new(
  'gemini/gemini-2.5-flash',
  api_key: ENV.fetch('GEMINI_API_KEY')
)
```

### OpenRouter

```ruby
gem 'dspy'
gem 'dspy-openai'
```

```ruby
DSPy::LM.new(
  'openrouter/openai/gpt-5-nano',
  api_key: ENV.fetch('OPENROUTER_API_KEY')
)
```

OpenRouter capabilities vary by the routed model. Optional `http_referrer:` and `x_title:` values add attribution headers; they do not change model support.

### Ollama

Install Ollama, pull a model, and use the OpenAI-compatible adapter:

```bash
ollama pull llama3.2
```

```ruby
gem 'dspy'
gem 'dspy-openai'
```

```ruby
DSPy::LM.new('ollama/llama3.2')
```

The default local endpoint does not need an API key. A remote or protected endpoint may require `base_url:` and `api_key:`. Model support for JSON schemas, media, and tools varies.

### RubyLLM

```ruby
gem 'dspy'
gem 'dspy-ruby_llm'
```

When RubyLLM is already configured and DSPy receives no `api_key`, `base_url`, `timeout`, or `max_retries` override, the adapter reuses the global RubyLLM configuration:

```ruby
DSPy::LM.new('ruby_llm/gpt-4o')
```

Passing one of those values creates or uses adapter-scoped configuration instead. Registry data, provider overrides, authentication, and features vary by provider, model, RubyLLM version, and provider SDK.

## Troubleshooting Setup

- `DSPy::LM::MissingAdapterError`: add the adapter gem named in the error and run `bundle install`.
- `KeyError`: export the variable read by `ENV.fetch`.
- `DSPy::LM::MissingAPIKeyError`: the adapter received no usable key; pass a nonblank credential.
- `DSPy::LM::UnsupportedProviderError`: use a supported model prefix from the table above.
- Connection or model errors: verify the endpoint, model identifier, account access, and provider-specific capability.

See [Troubleshooting](/dspy.rb/production/troubleshooting/) for runtime failures after setup.
