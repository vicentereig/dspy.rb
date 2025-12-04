# DSPy RubyLLM Adapter

Unified access to 12+ LLM providers through a single adapter using [RubyLLM](https://rubyllm.com).

## Installation

Add to your Gemfile:

```ruby
gem 'dspy-ruby_llm'
```

## Usage

### Using Existing RubyLLM Configuration (Recommended)

If you already have RubyLLM configured, DSPy will use your existing setup automatically:

```ruby
# Your existing RubyLLM configuration
RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
end

# DSPy uses your existing config - no api_key needed!
lm = DSPy::LM.new("ruby_llm/gpt-4o")
lm = DSPy::LM.new("ruby_llm/claude-sonnet-4")
```

### Model ID Format

Use `ruby_llm/{model_id}` format where `model_id` is the RubyLLM model identifier:

```ruby
# With explicit API key (creates scoped context)
lm = DSPy::LM.new("ruby_llm/gpt-4o", api_key: ENV['OPENAI_API_KEY'])

# Or use global RubyLLM config (no api_key needed)
lm = DSPy::LM.new("ruby_llm/gpt-4o")
lm = DSPy::LM.new("ruby_llm/claude-sonnet-4")
lm = DSPy::LM.new("ruby_llm/gemini-1.5-pro")
lm = DSPy::LM.new("ruby_llm/llama3.2")  # Ollama - auto-detected
```

The adapter automatically detects the provider from the model ID using RubyLLM's model registry.

### Provider Override

For custom deployments or models not in the registry, explicitly specify the provider:

```ruby
# AWS Bedrock (requires explicit provider)
lm = DSPy::LM.new("ruby_llm/anthropic.claude-3-5-sonnet",
  api_key: ENV['AWS_ACCESS_KEY_ID'],
  provider: 'bedrock',
  secret_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: 'us-east-1'
)

# VertexAI (requires explicit provider)
lm = DSPy::LM.new("ruby_llm/gemini-pro",
  api_key: 'your-project-id',
  provider: 'vertexai',
  location: 'us-central1'
)

# OpenRouter
lm = DSPy::LM.new("ruby_llm/anthropic/claude-3-opus",
  api_key: ENV['OPENROUTER_API_KEY'],
  provider: 'openrouter'
)

# Custom model with explicit provider
lm = DSPy::LM.new("ruby_llm/my-custom-model",
  api_key: ENV['OPENAI_API_KEY'],
  provider: 'openai',
  base_url: 'https://custom-endpoint.com/v1'
)
```

### Supported Providers

| Provider | Example Model ID | Notes |
|----------|------------------|-------|
| OpenAI | `ruby_llm/gpt-4o` | Auto-detected |
| Anthropic | `ruby_llm/claude-sonnet-4` | Auto-detected |
| Google Gemini | `ruby_llm/gemini-1.5-pro` | Auto-detected |
| DeepSeek | `ruby_llm/deepseek-chat` | Auto-detected |
| Mistral | `ruby_llm/mistral-large` | Auto-detected |
| Ollama | `ruby_llm/llama3.2` | Auto-detected, no API key needed |
| AWS Bedrock | `ruby_llm/anthropic.claude-3-5-sonnet` | Requires `provider: 'bedrock'` |
| VertexAI | `ruby_llm/gemini-pro` | Requires `provider: 'vertexai'` |
| OpenRouter | `ruby_llm/anthropic/claude-3-opus` | Requires `provider: 'openrouter'` |
| Perplexity | `ruby_llm/llama-3.1-sonar-large` | Requires `provider: 'perplexity'` |
| GPUStack | `ruby_llm/model-name` | Requires `provider: 'gpustack'` |

### Configuration Options

```ruby
# Common options
lm = DSPy::LM.new("ruby_llm/gpt-4o",
  api_key: ENV['OPENAI_API_KEY'],
  base_url: 'https://custom-endpoint.com/v1',  # Custom endpoint
  timeout: 120,                                  # Request timeout
  max_retries: 3,                               # Retry count
  structured_outputs: true                      # Enable JSON schema
)

# AWS Bedrock options
lm = DSPy::LM.new("ruby_llm/anthropic.claude-3",
  api_key: ENV['AWS_ACCESS_KEY_ID'],
  provider: 'bedrock',
  secret_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: 'us-east-1',
  session_token: ENV['AWS_SESSION_TOKEN']  # For temporary credentials
)

# VertexAI options
lm = DSPy::LM.new("ruby_llm/gemini-pro",
  api_key: 'your-project-id',
  provider: 'vertexai',
  location: 'us-central1'
)
```

### With DSPy Signatures

```ruby
class Summarize < DSPy::Signature
  description "Summarize the given text"

  input :text, String, desc: "Text to summarize"
  output :summary, String, desc: "Concise summary"
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new("ruby_llm/claude-sonnet-4", api_key: ENV['ANTHROPIC_API_KEY'])
end

summarizer = DSPy::Predict.new(Summarize)
result = summarizer.call(text: "Long article text here...")
puts result.summary
```

### Streaming

```ruby
lm = DSPy::LM.new("ruby_llm/gpt-4o", api_key: ENV['OPENAI_API_KEY'])

response = lm.chat(messages: [{ role: 'user', content: 'Tell me a story' }]) do |chunk|
  print chunk  # Print each chunk as it arrives
end
```

## Dependencies

This gem depends on:
- `dspy` (>= 0.30)
- `ruby_llm` (~> 1.3)

RubyLLM itself has minimal dependencies (Faraday, Zeitwerk, Marcel).

## Why Use This Adapter?

1. **Unified interface** - One API for all providers
2. **Lightweight** - RubyLLM has only 3 dependencies
3. **Provider coverage** - Access Bedrock, VertexAI, DeepSeek without separate adapters
4. **Built-in retries** - Automatic retry with exponential backoff
5. **Model registry** - 500+ models with capability detection and auto provider resolution

## Error Handling

The adapter maps RubyLLM errors to DSPy error types:

| RubyLLM Error | DSPy Error |
|---------------|------------|
| `UnauthorizedError` | `MissingAPIKeyError` |
| `RateLimitError` | `AdapterError` (with retry hint) |
| `ModelNotFoundError` | `AdapterError` |
| `BadRequestError` | `AdapterError` |
| `ConfigurationError` | `ConfigurationError` |
