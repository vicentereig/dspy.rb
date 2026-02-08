---
layout: docs
name: Installation
description: Install DSPy.rb and set up your development environment
breadcrumb:
- name: Getting Started
  url: "/getting-started/"
- name: Installation
  url: "/getting-started/installation/"
prev:
  name: Getting Started
  url: "/getting-started/"
next:
  name: Quick Start
  url: "/getting-started/quick-start/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-26 00:00:00 +0000
---
# Installation & Setup

## Installation

Add DSPy.rb to your Gemfile:

```ruby
gem 'dspy'
```

Or install it directly:

```bash
gem install dspy
```

For bleeding-edge features, you can install from GitHub:

```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

## Required Dependencies

DSPy.rb requires Ruby 3.3+ and automatically installs these core dependencies:

- **Core**: dry-configurable (~> 1.0), dry-logger (~> 1.0), async (~> 2.29), concurrent-ruby (~> 1.3)
- **Sorbet integration**: sorbet-runtime (~> 0.5), sorbet-schema (~> 0.3), sorbet-baml (~> 0.5), sorbet-toon (~> 0.1)
- **Schema**: dspy-schema (~> 1.0.0)

LLM provider SDKs are **not** included in the core gem. Add the adapter gems you need (see below).

## Provider Adapter Gems

Provider SDKs now ship as side-loaded gems so you only install what you need. Add the adapter(s) that match the `DSPy::LM` providers you call:

```ruby
# Gemfile
gem 'dspy'           # core framework
gem 'dspy-openai'    # OpenAI, OpenRouter, or Ollama adapters
gem 'dspy-anthropic' # Claude adapters
gem 'dspy-gemini'    # Gemini adapters
gem 'dspy-ruby_llm'  # RubyLLM unified adapter (12+ providers)
```

Each adapter gem already depends on the official SDK (`openai`, `anthropic`, `gemini-ai`, `ruby_llm`), so you don't need to add those manually. DSPy auto-loads the adapters when the gem is present—no extra `require` needed. Read the adapter guides for the specifics:

- [OpenAI / OpenRouter / Ollama adapters](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/openai/README.md)
- [Anthropic adapters](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/anthropic/README.md)
- [Gemini adapters](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/gemini/README.md)
- [RubyLLM unified adapter](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/ruby_llm/README.md) (OpenAI, Anthropic, Gemini, Bedrock, VertexAI, DeepSeek, Mistral, Ollama, and more)

## Observability

DSPy.rb uses structured logging for observability. The logs can be parsed and sent to any monitoring platform you prefer.

## Configuration

### Basic Configuration

```ruby
# Configure DSPy with your LLM provider
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  # or
  c.lm = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: ENV['ANTHROPIC_API_KEY'])
  # or use Ollama for local models
  c.lm = DSPy::LM.new('ollama/llama3.2')
  # or use OpenRouter for access to multiple providers (auto-fallback enabled)
  c.lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free', api_key: ENV['OPENROUTER_API_KEY'])
  # or use RubyLLM for unified access (uses your existing RubyLLM config)
  c.lm = DSPy::LM.new('ruby_llm/gpt-4o')
end
```

### Environment Variables

Set up your API keys:

```bash
# OpenAI
export OPENAI_API_KEY=sk-your-key-here

# Anthropic
export ANTHROPIC_API_KEY=sk-ant-your-key-here

# OpenRouter (access to multiple providers)
export OPENROUTER_API_KEY=sk-or-your-key-here

# Ollama (no API key needed for local instances)

# Optional: Observability platforms
export OTEL_SERVICE_NAME=my-dspy-app
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export LANGFUSE_SECRET_KEY=sk_your_key
export LANGFUSE_PUBLIC_KEY=pk_your_key
export NEW_RELIC_LICENSE_KEY=your_license_key
```

### Advanced Configuration

```ruby
DSPy.configure do |c|
  # LLM Configuration
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

  # Logging Configuration
  c.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(stream: 'log/dspy.log')
  end
end
```

## Provider Setup

### OpenAI Setup

1. Sign up at [OpenAI](https://openai.com/)
2. Create an API key
3. Set the environment variable:
   ```bash
   export OPENAI_API_KEY=sk-your-key-here
   ```
4. Use in DSPy:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
   end
   ```

### Anthropic Setup

1. Sign up at [Anthropic](https://console.anthropic.com/)
2. Create an API key
3. Set the environment variable:
   ```bash
   export ANTHROPIC_API_KEY=sk-ant-your-key-here
   ```
4. Use in DSPy:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: ENV['ANTHROPIC_API_KEY'])
   end
   ```

### OpenRouter Setup (Multiple Providers)

1. Sign up at [OpenRouter](https://openrouter.ai/)
2. Create an [API key](https://openrouter.ai/settings/keys)
3. Set the environment variable:
   ```bash
   export OPENROUTER_API_KEY=sk-or-your-key-here
   ```
4. Use in DSPy:
   ```ruby
   DSPy.configure do |c|
     # Basic usage - structured outputs enabled by default, auto-fallback if needed
     c.lm = DSPy::LM.new('openrouter/openai/gpt-5-nano',
       api_key: ENV['OPENROUTER_API_KEY']
    )
   end
   ```
5. With custom headers for app attribution:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('openrouter/anthropic/claude-3.5-sonnet',
       api_key: ENV['OPENROUTER_API_KEY'],
       http_referrer: 'https://your-app.com',
       x_title: 'Your App Name'
     )
   end
   ```
6. For models that don't support structured outputs, explicitly disable:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free',
       api_key: ENV['OPENROUTER_API_KEY'],
       structured_outputs: false  # Skip structured output attempt entirely
     )
   end
   ```
7. Models with native structured output support work seamlessly:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('openrouter/x-ai/grok-4-fast:free',
       api_key: ENV['OPENROUTER_API_KEY']
     )  # structured_outputs: true by default
   end
   ```

### Ollama Setup (Local Models)

1. Install Ollama from [ollama.com](https://ollama.com/)
2. Pull a model:
   ```bash
   ollama pull llama3.2
   ```
3. Use in DSPy (no API key needed):
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('ollama/llama3.2')
   end
   ```
4. For remote Ollama instances:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('ollama/llama3.2',
       base_url: 'https://my-ollama.example.com/v1',
       api_key: 'optional-auth-token'
     )
   end
   ```

### RubyLLM Setup (Unified Multi-Provider)

[RubyLLM](https://rubyllm.com) provides unified access to 12+ providers through a single lightweight adapter.

1. Add to your Gemfile:
   ```ruby
   gem 'dspy-ruby_llm'
   ```

2. **Option A**: Use existing RubyLLM configuration (recommended if you already use RubyLLM):
   ```ruby
   # Your existing RubyLLM setup
   RubyLLM.configure do |config|
     config.openai_api_key = ENV['OPENAI_API_KEY']
     config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
   end

   # DSPy uses your config automatically - no api_key needed!
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('ruby_llm/gpt-4o')
     # or
     c.lm = DSPy::LM.new('ruby_llm/claude-sonnet-4')
   end
   ```

3. **Option B**: Pass API key directly:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('ruby_llm/gpt-4o', api_key: ENV['OPENAI_API_KEY'])
   end
   ```

4. For AWS Bedrock, VertexAI, or other providers requiring explicit configuration:
   ```ruby
   DSPy.configure do |c|
     c.lm = DSPy::LM.new('ruby_llm/anthropic.claude-3-5-sonnet',
       provider: 'bedrock',
       api_key: ENV['AWS_ACCESS_KEY_ID'],
       secret_key: ENV['AWS_SECRET_ACCESS_KEY'],
       region: 'us-east-1'
     )
   end
   ```

**Supported providers**: OpenAI, Anthropic, Gemini, AWS Bedrock, VertexAI, Ollama, OpenRouter, DeepSeek, Mistral, Perplexity, GPUStack.

### Structured Outputs Support

Different providers support structured JSON extraction in different ways:

| Provider | Structured Outputs | How to Enable |
|----------|-------------------|---------------|
| **OpenAI** | ✅ Native JSON mode | `structured_outputs: true` |
| **Gemini** | ✅ Native JSON schema | `structured_outputs: true` |
| **Anthropic** | ✅ Tool-based extraction (default)<br/>✅ Enhanced prompting | `structured_outputs: true` (default)<br/>`structured_outputs: false` |
| **Ollama** | ✅ OpenAI-compatible JSON | `structured_outputs: true` |
| **OpenRouter** | ⚠️ Varies by model | Check model capabilities |
| **RubyLLM** | ✅ Via `with_schema` | `structured_outputs: true` (default) |

**Example:**
```ruby
# OpenAI with native structured outputs
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY'],
    structured_outputs: true
  )
end

# Anthropic - tool extraction by default (can be disabled)
DSPy.configure do |c|
  # Use tool-based extraction (default, most reliable)
  c.lm = DSPy::LM.new(
    'anthropic/claude-sonnet-4-5-20250929',
    api_key: ENV['ANTHROPIC_API_KEY'],
    structured_outputs: true  # Default, can be omitted
  )

  # Or use enhanced prompting instead
  # c.lm = DSPy::LM.new(
  #   'anthropic/claude-sonnet-4-5-20250929',
  #   api_key: ENV['ANTHROPIC_API_KEY'],
  #   structured_outputs: false  # Use enhanced prompting extraction
  # )
end
```

## Verification

Test your installation:

```ruby
require 'dspy'

# Configure with your provider
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# Test basic functionality
class TestSignature < DSPy::Signature
  description "Test DSPy installation"

  input do
    const :message, String
  end

  output do
    const :response, String
  end
end

predictor = DSPy::Predict.new(TestSignature)
result = predictor.call(message: "Hello, DSPy!")

puts "✅ DSPy is working! Response: #{result.response}"
```

## Troubleshooting

### Common Issues

**"LoadError: cannot load such file"**
- Make sure you've added the gem to your Gemfile and run `bundle install`

**"API key not found"**
- Verify your environment variables are set correctly
- Check that you're using the correct provider prefix (e.g., `openai/gpt-4`, not just `gpt-4`)

**"Unsupported provider"**
- DSPy requires provider prefixes. Use `openai/model-name`, `anthropic/model-name`, or `ollama/model-name`
- Legacy format without provider is no longer supported

**"Connection refused" with Ollama**
- Make sure Ollama is running: `ollama serve`
- Check that the model is downloaded: `ollama list`
- Verify the base URL if using a custom port

**Sorbet type errors**
- Make sure you're using the correct types in your signatures
- Check that input/output structs match your signature definitions

### Getting Help

- Check the [documentation](../README.md)
- Report issues on GitHub
- Email the maintainer directly for urgent issues
