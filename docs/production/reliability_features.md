# Reliability Features

DSPy.rb includes several reliability features to ensure robust JSON parsing and error recovery when working with LLMs.

## Retry Mechanisms

The retry handler provides progressive fallback between strategies with exponential backoff:

```ruby
# Automatic retry is enabled by default
DSPy.configure do |config|
  config.structured_outputs.retry_enabled = true    # Default: true
  config.structured_outputs.max_retries = 3         # Default: 3
  config.structured_outputs.fallback_enabled = true # Default: true
end
```

### How it works

1. **Initial attempt** with the best available strategy
2. **Retries** with the same strategy (with backoff) if parsing fails
3. **Fallback** to the next best strategy if max retries exceeded
4. **Progressive degradation** through all available strategies

### Retry counts by strategy

- **OpenAI Structured Output**: 1 retry (rarely benefits from more)
- **Anthropic Extraction**: 2 retries (can be variable)
- **Enhanced Prompting**: 3 retries (may need more attempts)

### Exponential backoff

```ruby
# In production mode
- Attempt 1: 0.5s base delay + jitter
- Attempt 2: 1.0s base delay + jitter  
- Attempt 3: 2.0s base delay + jitter
- Max delay: 10 seconds

# In test mode (config.test_mode = true)
- No delays between retries
```

## Caching

Performance optimization through intelligent caching of schemas and capabilities:

### Schema caching

OpenAI JSON schemas are cached to avoid regeneration:

```ruby
# Automatic caching with 1-hour TTL
schema = SchemaConverter.to_openai_format(MySignature)
# Subsequent calls use cached version
```

### Capability caching

Model capabilities are cached with 24-hour TTL:

```ruby
# First check performs detection
supports = SchemaConverter.supports_structured_outputs?("openai/gpt-4o")
# Subsequent checks use cache
```

### Cache management

```ruby
# Get cache statistics
stats = DSPy::LM.cache_manager.stats
# => { schema_entries: 5, capability_entries: 10, total_entries: 15 }

# Clear all caches
DSPy::LM.cache_manager.clear!
```

## Error Recovery

### Detailed error messages

JSON parsing errors include context for debugging:

```ruby
# Error includes original content length and provider info
"Failed to parse LLM response as JSON: unexpected token. Original content length: 156 chars"
```

### Strategy-specific error handling

Each strategy can handle errors differently:

```ruby
class CustomStrategy < DSPy::LM::Strategies::BaseStrategy
  def handle_error(error)
    # Return true to skip retries and move to next strategy
    # Return false to continue retry attempts
    error.is_a?(RateLimitError)
  end
end
```

## Configuration

### Global settings

```ruby
DSPy.configure do |config|
  # Retry configuration
  config.structured_outputs.retry_enabled = true
  config.structured_outputs.max_retries = 3
  config.structured_outputs.fallback_enabled = true
  
  # Test mode (disables delays)
  config.test_mode = true
end
```

### Per-request overrides

```ruby
# Disable retry for a specific LM instance
lm = DSPy::LM.new("openai/gpt-4o", 
                  api_key: key,
                  structured_outputs: true)

# Configure module without retry
module_instance.configure do |config|
  config.lm = lm
end
```

## Monitoring

The reliability features integrate with the instrumentation system:

```ruby
# Monitor retry attempts
DSPy::Instrumentation.subscribe do |event|
  if event.name == "dspy.lm.retry"
    puts "Retry attempt #{event.payload[:attempt]} for #{event.payload[:strategy]}"
  end
end

# Track cache performance  
DSPy::Instrumentation.subscribe do |event|
  if event.name == "dspy.cache.hit"
    puts "Cache hit for #{event.payload[:key]}"
  end
end
```

## Best Practices

1. **Enable structured outputs** when using supported OpenAI models
2. **Keep retry enabled** for production environments
3. **Use test mode** to disable delays during testing
4. **Monitor cache stats** to ensure good hit rates
5. **Set appropriate TTLs** based on your use case

## Troubleshooting

### High retry rates

If you're seeing many retries:
1. Check if you're using the optimal strategy for your model
2. Verify your signatures generate valid JSON schemas
3. Consider increasing max_retries for unreliable models

### Cache misses

If cache hit rate is low:
1. Check if signatures are being recreated unnecessarily
2. Verify TTL settings are appropriate
3. Ensure you're not clearing caches too frequently

### Strategy fallback issues

If strategies aren't falling back correctly:
1. Enable debug logging to see strategy selection
2. Check that fallback_enabled is true
3. Verify all strategies are properly configured