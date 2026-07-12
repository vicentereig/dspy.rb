---
layout: docs
title: Troubleshooting
description: Common issues and solutions for DSPy.rb
date: 2025-07-20 00:00:00 +0000
last_modified_at: 2025-08-08 00:00:00 +0000
---
# Troubleshooting

## Language Model Configuration

### Error: DSPy::ConfigurationError

**Cause**: The module cannot resolve a configured language model.

```ruby
DSPy::ConfigurationError: No language model configured for MyModule module.

To fix this, configure a language model either globally:

  DSPy.configure do |config|
    config.lm = DSPy::LM.new("openai/gpt-4", api_key: ENV["OPENAI_API_KEY"])
  end

Or on the module instance:

  module_instance.configure do |config|
    config.lm = DSPy::LM.new("anthropic/claude-3", api_key: ENV["ANTHROPIC_API_KEY"])
  end
```

**Correction**: Configure an LM globally or on the module instance as shown in the error. Prefer current model identifiers from the provider documentation.

## Gem Conflicts

### Warning: ruby-openai gem detected

**Cause**: DSPy uses the official OpenAI SDK. The community `ruby-openai` gem defines the same `OpenAI` namespace.

```
WARNING: ruby-openai gem detected. This may cause conflicts with DSPy's OpenAI integration.

DSPy uses the official 'openai' gem. The community 'ruby-openai' gem uses the same
OpenAI namespace and will cause conflicts.
```

**Correction**: Remove `ruby-openai` from the process that loads DSPy:

```ruby
# Gemfile
# Remove this line:
# gem 'ruby-openai'

# Install core plus the OpenAI adapter, which depends on the official SDK
gem 'dspy'
gem 'dspy-openai'
```

If the application needs both SDKs, isolate them in separate processes. Bundler groups help only when the conflicting gems are not loaded together.

### Namespace Conflicts

**Problem**: Both gems use the `OpenAI` namespace, causing method conflicts and unexpected behavior.

**Solution**: 
1. Use `dspy-openai`, which depends on the official `openai` gem
2. If migration is needed, update your code to use the official SDK's API:

```ruby
# ruby-openai (old)
client = OpenAI::Client.new(access_token: "key")
response = client.chat(parameters: { model: "gpt-4", messages: [...] })

# official openai SDK (new)
client = OpenAI::Client.new(api_key: "key")
response = client.chat.completions.create(model: "gpt-4", messages: [...])
```

## API Key Issues

### Error: DSPy::LM::MissingAPIKeyError

**Cause**: The adapter cannot find an API key in its argument or provider environment variable.

**Solution**: Set the API key via environment variable or parameter:

```ruby
# Via environment variable
export OPENAI_API_KEY=your-key-here
export ANTHROPIC_API_KEY=your-key-here
export GEMINI_API_KEY=your-key-here

# Via parameter
lm = DSPy::LM.new("openai/gpt-4", api_key: "your-key-here")
```

## JSON Parsing Issues

### Error: JSON parsing failures

**Cause**: The provider returned content that the configured JSON strategy could not parse or validate.

**Correction**: Use provider-native structured output when the selected model supports it. Otherwise inspect the raw response and simplify the signature or field descriptions.

```ruby
DSPy.configure do |config|
  # OpenAI with native structured outputs (recommended)
  config.lm = DSPy::LM.new(
    "openai/gpt-4o-mini",
    api_key: ENV["OPENAI_API_KEY"],
    structured_outputs: true
  )

  # Gemini with native structured outputs (recommended)
  # config.lm = DSPy::LM.new(
  #   "gemini/gemini-2.5-flash",
  #   api_key: ENV["GEMINI_API_KEY"],
  #   structured_outputs: true
  # )

  # Anthropic structured outputs
  # config.lm = DSPy::LM.new(
  #   "anthropic/claude-sonnet-4-5-20250929",
  #   api_key: ENV["ANTHROPIC_API_KEY"],
  #   structured_outputs: true
  # )

  # Anthropic with enhanced prompting (alternative)
  # config.lm = DSPy::LM.new(
  #   "anthropic/claude-sonnet-4-5-20250929",
  #   api_key: ENV["ANTHROPIC_API_KEY"],
  #   structured_outputs: false
  # )
end
```

Provider capabilities vary by model and SDK version. A provider prefix alone does not establish native schema support.

## Application State Issues

DSPy.rb does not provide a memory store. Keep conversation history, user preferences, and checkpoints in application-owned storage, then pass the relevant state into a signature as typed input.

If retained state grows without bound, inspect the application's database, cache, or session store. Define retention and compaction rules there rather than relying on an in-process DSPy object.

## Performance Issues

### Slow LLM responses

**Verification**: Inspect provider latency and DSPy spans before changing execution strategy.

**Corrections**:

1. Use a lower-latency model where its measured quality is sufficient.
2. Add application caching only when the cache key and invalidation rule are explicit.
3. Move independent batch work to an application job or concurrency boundary. DSPy does not schedule a batch automatically.

```ruby
# Use faster model for development
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-3.5-turbo") if Rails.env.development?
end
```

## Testing Issues

### VCR cassette errors

**Cause**: The recorded request no longer matches the adapter's current request shape.

**Solution**: Re-record cassettes when API changes:

```bash
# Delete specific cassette
rm spec/vcr_cassettes/my_test.yml

# Re-run test to record new cassette
bundle exec rspec spec/my_test_spec.rb
```

## Common Debugging Tips

1. **Enable debug logging**:

In development, DSPy.rb automatically logs to `log/development.log`. Simply tail the log file:

```bash
tail -f log/development.log
```

To enable debug level logging with output to stdout:

```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :string) do |s|
    s.add_backend(level: :debug, stream: $stdout)
  end
end
```

Or redirect logs to stdout using the environment variable:

```bash
DSPY_LOG=/dev/stdout ruby your_script.rb
```

2. **Check module configuration**:
```ruby
module = DSPy::Predict.new(MySignature)
puts module.lm # Should not be nil
puts module.config.inspect
```

3. **Verify API connectivity**:
```ruby
lm = DSPy::LM.new("openai/gpt-4")
response = lm.raw_chat([{ role: "user", content: "Reply with OK" }])
puts response.content
```

4. **Use JSON logging for production**:
```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :json) do |s|
    s.add_backend(stream: $stdout)
  end
end
```

## Getting Help

If you encounter issues not covered here:

1. Check the GitHub issues
2. Search the documentation
3. Create a new issue with:
   - Ruby version
   - DSPy version
   - Minimal reproduction code
   - Full error message and stack trace
