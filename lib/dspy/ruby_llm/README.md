# DSPy RubyLLM Adapter

Unified access to 12+ LLM providers through a single adapter using [RubyLLM](https://rubyllm.com).

## Installation

Add to your Gemfile:

```ruby
gem 'dspy-ruby_llm'
```

## Usage

### Provider ID Format

Use `ruby_llm/provider:model` format:

```ruby
# OpenAI
lm = DSPy::LM.new("ruby_llm/openai:gpt-4o", api_key: ENV['OPENAI_API_KEY'])

# Anthropic
lm = DSPy::LM.new("ruby_llm/anthropic:claude-sonnet-4", api_key: ENV['ANTHROPIC_API_KEY'])

# AWS Bedrock
lm = DSPy::LM.new("ruby_llm/bedrock:anthropic.claude-3-5-sonnet",
  api_key: ENV['AWS_ACCESS_KEY_ID'],
  secret_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: 'us-east-1'
)

# Google Gemini
lm = DSPy::LM.new("ruby_llm/gemini:gemini-1.5-pro", api_key: ENV['GEMINI_API_KEY'])

# Ollama (local)
lm = DSPy::LM.new("ruby_llm/ollama:llama3.2", api_key: nil, base_url: 'http://localhost:11434')

# OpenRouter
lm = DSPy::LM.new("ruby_llm/openrouter:anthropic/claude-3-opus", api_key: ENV['OPENROUTER_API_KEY'])

# DeepSeek
lm = DSPy::LM.new("ruby_llm/deepseek:deepseek-chat", api_key: ENV['DEEPSEEK_API_KEY'])

# Mistral
lm = DSPy::LM.new("ruby_llm/mistral:mistral-large", api_key: ENV['MISTRAL_API_KEY'])
```

### Supported Providers

| Provider | Example Model ID |
|----------|------------------|
| OpenAI | `ruby_llm/openai:gpt-4o` |
| Anthropic | `ruby_llm/anthropic:claude-sonnet-4` |
| Google Gemini | `ruby_llm/gemini:gemini-1.5-pro` |
| AWS Bedrock | `ruby_llm/bedrock:anthropic.claude-3-5-sonnet` |
| VertexAI | `ruby_llm/vertexai:gemini-pro` |
| Ollama | `ruby_llm/ollama:llama3.2` |
| OpenRouter | `ruby_llm/openrouter:anthropic/claude-3-opus` |
| DeepSeek | `ruby_llm/deepseek:deepseek-chat` |
| Mistral | `ruby_llm/mistral:mistral-large` |
| Perplexity | `ruby_llm/perplexity:llama-3.1-sonar-large` |
| GPUStack | `ruby_llm/gpustack:model-name` |

### Configuration Options

```ruby
# Common options
lm = DSPy::LM.new("ruby_llm/openai:gpt-4o",
  api_key: ENV['OPENAI_API_KEY'],
  base_url: 'https://custom-endpoint.com/v1',  # Custom endpoint
  timeout: 120,                                  # Request timeout
  max_retries: 3,                               # Retry count
  structured_outputs: true                      # Enable JSON schema
)

# AWS Bedrock options
lm = DSPy::LM.new("ruby_llm/bedrock:anthropic.claude-3",
  api_key: ENV['AWS_ACCESS_KEY_ID'],
  secret_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: 'us-east-1',
  session_token: ENV['AWS_SESSION_TOKEN']  # For temporary credentials
)

# VertexAI options
lm = DSPy::LM.new("ruby_llm/vertexai:gemini-pro",
  api_key: 'your-project-id',
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
  config.lm = DSPy::LM.new("ruby_llm/anthropic:claude-sonnet-4", api_key: ENV['ANTHROPIC_API_KEY'])
end

summarizer = DSPy::Predict.new(Summarize)
result = summarizer.call(text: "Long article text here...")
puts result.summary
```

### Streaming

```ruby
lm = DSPy::LM.new("ruby_llm/openai:gpt-4o", api_key: ENV['OPENAI_API_KEY'])

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
5. **Model registry** - 500+ models with capability detection

## Error Handling

The adapter maps RubyLLM errors to DSPy error types:

| RubyLLM Error | DSPy Error |
|---------------|------------|
| `UnauthorizedError` | `MissingAPIKeyError` |
| `RateLimitError` | `AdapterError` (with retry hint) |
| `ModelNotFoundError` | `AdapterError` |
| `BadRequestError` | `AdapterError` |
| `ConfigurationError` | `ConfigurationError` |
