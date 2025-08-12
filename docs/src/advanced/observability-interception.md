---
layout: docs
name: Advanced Observability Interception
description: Real-time event interception and custom instrumentation patterns
breadcrumb:
  - name: Advanced
    url: /advanced/
  - name: Observability Interception
    url: /advanced/observability-interception/
prev:
  name: Stateful Agents
  url: /advanced/stateful-agents/
next:
  name: Python Comparison
  url: /advanced/python-comparison/
---

# Advanced Observability Interception

How to intercept DSPy.rb events before they're logged. Based on the current implementation in `lib/dspy/context.rb` and `lib/dspy/observability.rb`.

## Three Interception Points

1. **Logger Backend** - Override `Dry::Logger::Backends::Stream#call`
2. **Context.with_span** - Prepend to intercept span creation
3. **OpenTelemetry** - Add custom `SpanProcessor` (when Langfuse configured)

## Method 1: Custom Logger Backend

```ruby
require 'dry/logger'

class EventInterceptorBackend < Dry::Logger::Backends::Stream
  def initialize(stream:, **options)
    super
    @event_handlers = {}
  end
  
  # Register a handler for specific events
  def on_event(event_name, &block)
    @event_handlers[event_name] = block
  end
  
  def call(entry)
    # Process the event before logging
    if handler = @event_handlers[entry[:event]]
      handler.call(entry)
    end
    
    # Continue with normal logging
    super
  end
end

# Configure DSPy with custom backend
backend = EventInterceptorBackend.new(stream: "log/production.log")

# Register event handlers
backend.on_event('span.attributes') do |entry|
  if entry['gen_ai.usage.total_tokens']
    puts "Tokens used: #{entry['gen_ai.usage.total_tokens']}"
  end
end

DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy) do |logger|
    logger.add_backend(backend)
  end
end
```

### Example: Filter Sensitive Data

```ruby
class FilteringBackend < Dry::Logger::Backends::Stream
  SENSITIVE_KEYS = %w[api_key password token secret email ssn].freeze
  
  def call(entry)
    # Deep clone to avoid modifying original
    filtered_entry = entry.dup
    
    # Recursively filter sensitive keys
    filter_sensitive!(filtered_entry)
    
    # Log the filtered version
    super(filtered_entry)
  end
  
  private
  
  def filter_sensitive!(obj)
    case obj
    when Hash
      obj.each do |key, value|
        if SENSITIVE_KEYS.any? { |k| key.to_s.downcase.include?(k) }
          obj[key] = '[REDACTED]'
        else
          filter_sensitive!(value)
        end
      end
    when Array
      obj.each { |item| filter_sensitive!(item) }
    end
  end
end
```

### Example: Collect Metrics

```ruby
class MetricsBackend < Dry::Logger::Backends::Stream
  def initialize(stream:, metrics_client: nil, **options)
    super(stream: stream, **options)
    @metrics = metrics_client || StatsD.new
    @token_totals = Concurrent::Hash.new(0)
  end
  
  def call(entry)
    # Extract metrics asynchronously
    Concurrent::Promise.execute do
      extract_metrics(entry)
    end
    
    # Don't block on metrics collection
    super
  end
  
  private
  
  def extract_metrics(entry)
    case entry[:event]
    when 'span.end'
      if entry[:operation] == 'llm.generate'
        @metrics.timing('llm.duration', entry[:duration_ms])
      end
    when 'span.attributes'
      if tokens = entry['gen_ai.usage.total_tokens']
        model = entry['gen_ai.request.model']
        @metrics.increment('llm.tokens', tokens, tags: ["model:#{model}"])
        @token_totals[model] += tokens
      end
    end
  rescue => e
    # Never let metrics break the main flow
    DSPy.logger.error("Metrics extraction failed: #{e.message}")
  end
end
```

## Method 2: Context.with_span Prepend

```ruby
module ContextInterceptor
  def with_span(operation:, **attributes)
    before_span(operation, attributes)
    result = super
    after_span(operation, attributes, result)
    result
  rescue => e
    on_span_error(operation, attributes, e)
    raise
  end
  
  private
  
  def before_span(operation, attributes)
    if operation == 'llm.generate'
      RateLimiter.check!(attributes['gen_ai.request.model'])
    end
  end
  
  def after_span(operation, attributes, result)
    if operation == 'llm.generate' && attributes['gen_ai.usage.total_tokens']
      CostTracker.record(
        model: attributes['gen_ai.request.model'],
        tokens: attributes['gen_ai.usage.total_tokens']
      )
    end
  end
  
  def on_span_error(operation, attributes, error)
    AlertManager.notify(operation: operation, error: error.message)
  end
end

DSPy::Context.singleton_class.prepend(ContextInterceptor)
```

### Example: Add Attributes

```ruby
module SpanEnricher
  def with_span(operation:, **attributes)
    attributes[:environment] = Rails.env
    attributes[:user_id] = Current.user&.id
    super
  end
end

DSPy::Context.singleton_class.prepend(SpanEnricher)
```

## Method 3: OpenTelemetry Processor

```ruby
class CustomSpanProcessor < OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor
  def on_end(span)
    if span.name == 'llm.generate'
      tokens = span.attributes['gen_ai.usage.total_tokens']
      if tokens
        Metrics.increment('llm.tokens', tokens)
      end
    end
    super
  end
end

OpenTelemetry::SDK.configure do |config|
  exporter = OpenTelemetry::Exporter::OTLP::Exporter.new
  config.add_span_processor(CustomSpanProcessor.new(exporter))
end
```

### Example: Sampling

```ruby
class SamplingSpanProcessor < OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor
  def on_end(span)
    # Always export errors, sample 10% of others
    if span.status.code == OpenTelemetry::Trace::Status::ERROR || rand < 0.1
      super
    end
  end
end
```

## Complete Example: Token Cost Tracker

```ruby
class TokenCostTracker
  PRICING = { # per 1K tokens
    'gpt-4' => { input: 0.03, output: 0.06 },
    'gpt-3.5-turbo' => { input: 0.0005, output: 0.0015 }
  }
  
  def self.install!
    @costs = Hash.new(0.0)
    
    # Custom logger backend
    backend = Class.new(Dry::Logger::Backends::Stream) do
      def call(entry)
        if entry[:event] == 'span.attributes' && entry['gen_ai.usage.total_tokens']
          TokenCostTracker.track(entry)
        end
        super
      end
    end
    
    DSPy.configure do |config|
      config.logger = Dry.Logger(:dspy) do |logger|
        logger.add_backend(backend.new(stream: "log/dspy.log"))
      end
    end
  end
  
  def self.track(entry)
    model = entry['gen_ai.request.model']
    input = entry['gen_ai.usage.prompt_tokens'] || 0
    output = entry['gen_ai.usage.completion_tokens'] || 0
    
    pricing = PRICING[model] || PRICING['gpt-3.5-turbo']
    cost = (input / 1000.0) * pricing[:input] + (output / 1000.0) * pricing[:output]
    
    @costs[model] += cost
    puts "#{model}: $#{'%.4f' % cost} (total: $#{'%.2f' % @costs[model]})"
  end
end

TokenCostTracker.install!
```

## Error Handling

```ruby
module SafeInterceptor
  def with_span(operation:, **attributes)
    super
  rescue => e
    DSPy.logger.error("Interceptor error: #{e.message}")
    # Continue without interception
    yield
  end
end
```

## Testing

```ruby
RSpec.describe "Custom Interceptor" do
  let(:interceptor) { EventInterceptorBackend.new(stream: StringIO.new) }
  
  it "processes events correctly" do
    events_received = []
    
    interceptor.on_event('test.event') do |entry|
      events_received << entry
    end
    
    interceptor.call(event: 'test.event', data: 'test')
    
    expect(events_received).to have(1).item
    expect(events_received.first[:data]).to eq('test')
  end
end
```

## Example: Rate Limiting

```ruby
class RateLimitInterceptor
  def self.install!
    DSPy::Context.singleton_class.prepend(Module.new do
      def with_span(operation:, **attributes)
        if operation == 'llm.generate'
          model = attributes['gen_ai.request.model']
          
          Redis.current.multi do |r|
            key = "rate_limit:#{model}:#{Time.now.to_i / 60}"
            r.incr(key)
            r.expire(key, 120)
          end.tap do |count, _|
            if count > 100 # 100 requests per minute
              raise "Rate limit exceeded for #{model}"
            end
          end
        end
        
        super
      end
    end)
  end
end
```

## Example: Audit Log

```ruby
class AuditInterceptor
  def self.install!
    backend = Class.new(Dry::Logger::Backends::Stream) do
      def call(entry)
        if entry[:event] == 'llm.generate'
          AuditLog.create!(
            user_id: Current.user&.id,
            action: 'llm_request',
            model: entry['gen_ai.request.model'],
            tokens: entry['gen_ai.usage.total_tokens'],
            timestamp: Time.current
          )
        end
        super
      end
    end
    
    # Add to existing logger configuration
    DSPy.logger.add_backend(backend.new(stream: "log/audit.log"))
  end
end
```

## Troubleshooting

- **Not firing**: Install interceptor before DSPy operations
- **Performance**: Use async/sampling for heavy work
- **Memory**: Clear state periodically

## References

- `lib/dspy/context.rb:15-60` - Context implementation
- `lib/dspy/observability.rb:76-92` - OpenTelemetry integration
- `lib/dspy/lm.rb:231-239` - Token usage attributes
- [ADR-007](/adr/007-observability-event-interception-architecture/) - Architecture decision
- [GitHub Issue #69](https://github.com/vicentereig/dspy.rb/issues/69) - Proposed middleware API