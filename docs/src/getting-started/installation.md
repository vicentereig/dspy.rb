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
gem 'dspy', '~> 0.20.0'
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

DSPy.rb requires Ruby 3.3+ and includes these core dependencies:

```ruby
# Core dependencies (automatically installed)
gem 'dry-configurable', '~> 1.0'
gem 'dry-logger', '~> 1.0'
gem 'async', '~> 2.23'

# Official LM provider clients
gem 'openai', '~> 0.9.0'
gem 'anthropic', '~> 1.5.0'
# Note: Ollama support is built-in via OpenAI compatibility layer

# Sorbet integration dependencies
gem 'sorbet-runtime', '~> 0.5'
gem 'sorbet-schema', '~> 0.3'
```

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
end
```

### Environment Variables

Set up your API keys:

```bash
# OpenAI
export OPENAI_API_KEY=sk-your-key-here

# Anthropic
export ANTHROPIC_API_KEY=sk-ant-your-key-here

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
- Report issues on [GitHub](https://github.com/vicentereig/dspy.rb/issues)
- Email the maintainer directly for urgent issues