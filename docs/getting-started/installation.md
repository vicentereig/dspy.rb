# Installation & Setup

## Installation

Skip the gem for now - install straight from this repo while I prep the first release:

```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

## Required Dependencies

DSPy.rb requires Ruby 3.3+ and includes these core dependencies:

```ruby
# Core dependencies (automatically installed)
gem 'dry-configurable', '~> 1.0'
gem 'dry-logger', '~> 1.0'
gem 'dry-monitor', '~> 1.0'
gem 'async', '~> 2.23'

# Official LM provider clients
gem 'openai', '~> 0.9.0'
gem 'anthropic', '~> 1.1.0'

# Sorbet integration dependencies
gem 'sorbet-runtime', '~> 0.5'
gem 'sorbet-schema', '~> 0.3'
```

## Optional Observability Dependencies

Add any of these gems for enhanced observability:

```ruby
# OpenTelemetry (distributed tracing)
gem 'opentelemetry-api'
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'

# New Relic (APM)
gem 'newrelic_rpm'

# Langfuse (LLM observability) 
gem 'langfuse'
```

DSPy automatically detects and integrates with available platforms - no configuration required!

## Configuration

### Basic Configuration

```ruby
# Configure DSPy with your LLM provider
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  # or
  c.lm = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: ENV['ANTHROPIC_API_KEY'])
end
```

### Environment Variables

Set up your API keys:

```bash
# OpenAI
export OPENAI_API_KEY=sk-your-key-here

# Anthropic
export ANTHROPIC_API_KEY=sk-ant-your-key-here

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
  
  # Instrumentation Configuration
  c.instrumentation.enabled = true
  c.instrumentation.subscribers = ['logger']  # Available: logger, otel, newrelic, langfuse
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
- DSPy requires provider prefixes. Use `openai/model-name` or `anthropic/model-name`
- Legacy format without provider is no longer supported

**Sorbet type errors**
- Make sure you're using the correct types in your signatures
- Check that input/output structs match your signature definitions

### Getting Help

- Check the [documentation](../README.md)
- Report issues on [GitHub](https://github.com/vicentereig/dspy.rb/issues)
- Email the maintainer directly for urgent issues