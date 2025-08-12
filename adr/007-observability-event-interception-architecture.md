# ADR-007: Observability Event Interception Architecture

## Status
Accepted

## Context

DSPy.rb logs events through Dry::Logger and optionally exports spans to Langfuse via OpenTelemetry. Users need to intercept events for:

- Token cost tracking
- Rate limiting
- Metrics collection
- Data filtering

The code supports interception but it's undocumented.

## Decision

Document the three interception points in DSPy.rb:

1. **Logger Backend**: Subclass `Dry::Logger::Backends::Stream`
2. **Context.with_span**: Use `prepend` or `alias_method`
3. **OpenTelemetry**: Add custom `SpanProcessor`

## Architecture

### Event Flow (from lib/dspy/lm.rb:209-246)

```
LM#instrument_lm_request (line 209)
  → Context.with_span (lib/dspy/context.rb:15)
    → DSPy.log (lib/dspy.rb:36)
    → Observability.start_span (lib/dspy/observability.rb:76)
```

### Interception Points

1. **Logger Backend** (`lib/dspy.rb:49-75`)
   - Override `Dry::Logger::Backends::Stream#call(entry)`
   - Receives all log entries before writing

2. **Context.with_span** (`lib/dspy/context.rb:15-60`)
   - Prepend module to intercept span start/end
   - Access to operation name and attributes

3. **OpenTelemetry** (`lib/dspy/observability.rb:39-50`)
   - Add `BatchSpanProcessor` with custom exporter
   - Only when Langfuse env vars present

### Token Usage Path (lib/dspy/lm.rb:231-239)

```ruby
# Token data available in span.attributes event:
'gen_ai.usage.prompt_tokens' => usage.input_tokens
'gen_ai.usage.completion_tokens' => usage.output_tokens  
'gen_ai.usage.total_tokens' => usage.total_tokens
'gen_ai.request.model' => model
```

## Consequences

### Positive
- Multiple interception points available
- Thread-safe (context per thread)
- No core code changes needed

### Negative
- Undocumented capability
- Requires metaprogramming
- May break with updates

## Implementation Examples

### Logger Backend (no monkey-patching)
```ruby
class TokenLogger < Dry::Logger::Backends::Stream
  def call(entry)
    if entry['gen_ai.usage.total_tokens']
      # Process tokens
    end
    super
  end
end
```

### Context Prepend (access to full context)
```ruby
DSPy::Context.singleton_class.prepend(Module.new do
  def with_span(operation:, **attributes)
    # Pre/post hooks
    super
  end
end)
```

## Documentation Created

1. `docs/src/advanced/observability-interception.md` - Working examples for all three methods
2. GitHub Issue #69 - Proposes native middleware API to avoid monkey-patching

## Future Work

Replace metaprogramming with middleware API:

```ruby
DSPy.configure do |config|
  config.observability.add_middleware(TokenCostTracker)
end
```

## References

- `lib/dspy/context.rb:15-60` - Context.with_span implementation
- `lib/dspy/observability.rb:76-92` - OpenTelemetry span creation
- `lib/dspy/lm.rb:209-246` - Token usage in instrument_lm_request
- `lib/dspy.rb:49-75` - Logger configuration