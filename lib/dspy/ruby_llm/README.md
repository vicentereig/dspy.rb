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

# For models not in RubyLLM registry, specify provider explicitly
lm = DSPy::LM.new("ruby_llm/llama3.2", provider: 'ollama')
```

The adapter detects the provider from RubyLLM's model registry. For models not in the registry, use the `provider:` option.

### Provider Override

For custom deployments or models not in the registry, explicitly specify the provider:

```ruby
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

# AWS Bedrock - configure RubyLLM globally first
RubyLLM.configure do |c|
  c.bedrock_api_key = ENV['AWS_ACCESS_KEY_ID']
  c.bedrock_secret_key = ENV['AWS_SECRET_ACCESS_KEY']
  c.bedrock_region = 'us-east-1'
end
lm = DSPy::LM.new("ruby_llm/anthropic.claude-3-5-sonnet", provider: 'bedrock')

# VertexAI - configure RubyLLM globally first
RubyLLM.configure do |c|
  c.vertexai_project_id = 'your-project-id'
  c.vertexai_location = 'us-central1'
end
lm = DSPy::LM.new("ruby_llm/gemini-pro", provider: 'vertexai')
```

### Supported Providers

| Provider | Example Model ID | Notes |
|----------|------------------|-------|
| OpenAI | `ruby_llm/gpt-4o` | In RubyLLM registry |
| Anthropic | `ruby_llm/claude-sonnet-4` | In RubyLLM registry |
| Google Gemini | `ruby_llm/gemini-1.5-pro` | In RubyLLM registry |
| DeepSeek | `ruby_llm/deepseek-chat` | In RubyLLM registry |
| Mistral | `ruby_llm/mistral-large` | In RubyLLM registry |
| Ollama | `ruby_llm/llama3.2` | Use `provider: 'ollama'`, no API key needed |
| AWS Bedrock | `ruby_llm/anthropic.claude-3-5-sonnet` | Configure RubyLLM globally |
| VertexAI | `ruby_llm/gemini-pro` | Configure RubyLLM globally |
| OpenRouter | `ruby_llm/anthropic/claude-3-opus` | Use `provider: 'openrouter'` |
| Perplexity | `ruby_llm/llama-3.1-sonar-large` | Use `provider: 'perplexity'` |
| GPUStack | `ruby_llm/model-name` | Use `provider: 'gpustack'` |

### Configuration Options

```ruby
lm = DSPy::LM.new("ruby_llm/gpt-4o",
  api_key: ENV['OPENAI_API_KEY'],       # API key (or use global RubyLLM config)
  base_url: 'https://custom.com/v1',    # Custom endpoint
  timeout: 120,                          # Request timeout in seconds
  max_retries: 3,                        # Retry count
  structured_outputs: true               # Enable JSON schema (default: true)
)
```

For providers with non-standard auth (Bedrock, VertexAI), configure RubyLLM globally - see examples above.

### With DSPy Signatures

```ruby
class Summarize < DSPy::Signature
  description "Summarize the given text"

  input do
    const :text, String
  end

  output do
    const :summary, String
  end
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new("ruby_llm/claude-sonnet-4")
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
- `dspy` (>= 0.32)
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
