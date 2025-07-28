# Add Ollama Support to DSPy.rb

## Overview
Add support for Ollama models in DSPy.rb, enabling users to run LLMs locally or on self-hosted infrastructure using Ollama's OpenAI-compatible API.

## Motivation
- **Local Development**: Run LLMs locally without API costs during development
- **Privacy**: Keep data on-premises for sensitive applications
- **Cost Efficiency**: No per-token API charges for self-hosted models
- **Model Variety**: Access to many open-source models (Llama 3.2, Mistral, Phi, etc.)
- **OpenAI Compatibility**: Ollama provides an OpenAI-compatible endpoint, making integration straightforward

## Implementation Plan

### 1. Create OllamaAdapter
```ruby
# lib/dspy/lm/adapters/ollama_adapter.rb
class OllamaAdapter < OpenAIAdapter
  DEFAULT_BASE_URL = 'http://localhost:11434/v1'
  
  def initialize(model:, api_key: nil, base_url: nil, structured_outputs: true)
    # API key optional for local instances
    # Required for remote/authenticated instances
    api_key ||= 'ollama'
    base_url ||= DEFAULT_BASE_URL
    
    # Custom initialization to control base URL
    @model = model
    @api_key = api_key
    @base_url = base_url
    @structured_outputs_enabled = structured_outputs
    validate_configuration!
    
    @client = OpenAI::Client.new(
      api_key: @api_key,
      base_url: @base_url
    )
  end
end
```

### 2. Update AdapterFactory
- Add `'ollama' => 'OllamaAdapter'` to ADAPTER_MAP
- Include ollama in provider options handling

### 3. Strategy Support
- Update OpenAIStructuredOutputStrategy to recognize OllamaAdapter
- Implement fallback mechanism for structured outputs that may not fully comply with OpenAI spec

### 4. Configuration Examples
```ruby
# Local Ollama (default)
lm = DSPy::LM.new('ollama/llama3.2')

# Remote Ollama with authentication
lm = DSPy::LM.new('ollama/llama3.2',
  base_url: 'https://my-ollama.example.com/v1',
  api_key: 'my-auth-token'
)

# Disable structured outputs if needed
lm = DSPy::LM.new('ollama/llama3.2', structured_outputs: false)
```

## Technical Details

### API Compatibility
- Ollama provides OpenAI-compatible endpoints at `/v1/chat/completions`
- Supports basic `response_format: { type: 'json_object' }`
- May have limitations with full OpenAI structured output spec

### Token Usage
- Ollama returns usage information in OpenAI format
- Compatible with existing token tracking instrumentation

### Model Detection
- All Ollama models assumed to support basic JSON mode
- Graceful fallback to enhanced prompting if structured output fails

## Testing Strategy

### Integration Tests
- Basic completion
- Structured outputs with various signatures
- Token usage tracking
- Instrumentation events
- Chain of Thought reasoning
- Remote configuration validation

### VCR Recordings
- Record actual Ollama API interactions
- Test against llama3.2 model locally

## Documentation Updates

### Files to Update
- `docs/src/getting-started/installation.md` - Add Ollama setup instructions
- `docs/src/core-concepts/index.md` - Include Ollama in provider list
- `docs/src/llms.txt.erb` and `llms-full.txt.erb` - Add Ollama examples
- `README.md` - Add Ollama to supported providers

### Blog Post Topics
- Type-safe Ruby with local LLMs
- Cost-effective development with Ollama
- Privacy-first LLM applications
- Comparing Ollama vs cloud providers

## Example Usage

```ruby
require 'dspy'

# Define a type-safe signature
class ProductAnalysis < DSPy::Signature
  input do
    const :description, String
  end
  output do
    const :category, String
    const :sentiment, String
    const :key_features, T::Array[String]
  end
end

# Use with local Ollama
lm = DSPy::LM.new('ollama/llama3.2')
DSPy.config.lm = lm

analyzer = DSPy::Predict.new(ProductAnalysis)
result = analyzer.forward(
  description: "Lightweight laptop with 16GB RAM and all-day battery"
)

# Type-safe access to results
puts "Category: #{result.category}"
puts "Sentiment: #{result.sentiment}"
puts "Features: #{result.key_features.join(', ')}"
```

## Benefits

1. **Type Safety**: Full Sorbet type checking with local models
2. **Cost Savings**: No API charges for development/testing
3. **Privacy**: Data never leaves your infrastructure
4. **Flexibility**: Switch between local and cloud providers easily
5. **Performance**: Low latency for local inference

## Next Steps

1. ✅ Implement OllamaAdapter
2. ✅ Create comprehensive integration tests
3. ✅ Verify structured output support
4. 📝 Update documentation
5. 📝 Write announcement blog post
6. 🚀 Release in v0.15.0

## References
- [Ollama API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [Ollama OpenAI Compatibility](https://ollama.com/blog/openai-compatibility)
- [DSPy.rb Documentation](https://vicentereig.github.io/dspy.rb/)