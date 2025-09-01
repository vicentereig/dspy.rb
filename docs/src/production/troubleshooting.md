---
layout: docs
title: Troubleshooting
description: Common issues and solutions for DSPy.rb
date: 2025-07-20 00:00:00 +0000
last_modified_at: 2025-08-08 00:00:00 +0000
---
# Troubleshooting Guide

This guide covers common issues you might encounter when using DSPy.rb and their solutions.

## Language Model Configuration

### Error: NoMethodError: undefined method 'model' for nil

**Problem**: This error occurs when a DSPy module doesn't have a language model configured.

```ruby
module = DSPy::Predict.new(MySignature)
module.forward(input: "test")
# => NoMethodError: undefined method 'model' for nil
```

**Solution**: Configure a language model either globally or at the module level.

```ruby
# Option 1: Global configuration
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4", api_key: ENV["OPENAI_API_KEY"])
end

# Option 2: Module-level configuration
module = DSPy::Predict.new(MySignature)
module.configure do |config|
  config.lm = DSPy::LM.new("anthropic/claude-3", api_key: ENV["ANTHROPIC_API_KEY"])
end
```

### Error: DSPy::ConfigurationError

**Problem**: Starting from version 0.9.0, DSPy provides clearer error messages when LM is not configured.

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

**Solution**: Follow the instructions in the error message to configure an LM.

## Gem Conflicts

### Warning: ruby-openai gem detected

**Problem**: DSPy uses the official OpenAI SDK, which conflicts with the community `ruby-openai` gem.

```
WARNING: ruby-openai gem detected. This may cause conflicts with DSPy's OpenAI integration.

DSPy uses the official 'openai' gem. The community 'ruby-openai' gem uses the same
OpenAI namespace and will cause conflicts.
```

**Solution**: Remove `ruby-openai` from your Gemfile and use the official gem:

```ruby
# Gemfile
# Remove this line:
# gem 'ruby-openai'

# DSPy already includes the official gem internally
gem 'dspy'
```

If you need both gems for different parts of your application, consider isolating them in separate processes or using bundler groups to load them conditionally.

### Namespace Conflicts

**Problem**: Both gems use the `OpenAI` namespace, causing method conflicts and unexpected behavior.

**Solution**: 
1. Use only the official `openai` gem that DSPy depends on
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

**Problem**: API key is not provided for the language model.

**Solution**: Set the API key via environment variable or parameter:

```ruby
# Via environment variable
export OPENAI_API_KEY=your-key-here
export ANTHROPIC_API_KEY=your-key-here

# Via parameter
lm = DSPy::LM.new("openai/gpt-4", api_key: "your-key-here")
```

## JSON Parsing Issues

### Error: JSON parsing failures with structured outputs

**Problem**: LLM returns invalid JSON that can't be parsed.

**Solution**: DSPy automatically retries with fallback strategies:

```ruby
# Configure retry behavior
DSPy.configure do |config|
  config.structured_outputs.retry_enabled = true
  config.structured_outputs.max_retries = 3
  config.structured_outputs.fallback_enabled = true
end
```

## Memory Issues

### Error: Memory storage full

**Problem**: In-memory storage reaches capacity limits.

**Solution**: Configure memory limits or use persistent storage:

```ruby
# Configure memory limits
memory = DSPy::Memory.new(
  max_entries: 1000,
  compaction_enabled: true
)

# Use persistent storage
memory = DSPy::Memory.new(
  storage: :file,
  path: "data/memory.json"
)
```

## Performance Issues

### Slow LLM responses

**Problem**: API calls taking too long.

**Solution**: 
1. Use smaller models for development
2. Enable caching for repeated calls
3. Use async processing for batch operations

```ruby
# Use faster model for development
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-3.5-turbo") if Rails.env.development?
end
```

## Testing Issues

### VCR cassette errors

**Problem**: Tests fail due to outdated VCR cassettes.

**Solution**: Re-record cassettes when API changes:

```bash
# Delete specific cassette
rm spec/fixtures/vcr_cassettes/my_test.yml

# Re-run test to record new cassette
bundle exec rspec spec/my_test_spec.rb
```

## Common Debugging Tips

1. **Enable debug logging**:
```ruby
DSPy.configure do |config|
  config.logger.level = :debug
end
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
response = lm.generate("Test prompt")
puts response
```

4. **Use logging for debugging**:
```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :json)
end
```

## Getting Help

If you encounter issues not covered here:

1. Check the [GitHub issues](https://github.com/vicentereig/dspy.rb/issues)
2. Search the documentation
3. Create a new issue with:
   - Ruby version
   - DSPy version
   - Minimal reproduction code
   - Full error message and stack trace