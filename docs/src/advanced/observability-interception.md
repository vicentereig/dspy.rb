---
layout: docs
name: Event System vs Monkey-Patching
description: Compare the new event system with old interception approaches
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: Event System vs Monkey-Patching
  url: "/advanced/observability-interception/"
prev:
  name: Stateful Agents
  url: "/advanced/stateful-agents/"
next:
  name: Python Comparison
  url: "/advanced/python-comparison/"
date: 2025-09-03 00:00:00 +0000
---
# Event System vs Monkey-Patching

The DSPy.rb event system eliminates the need for complex monkey-patching and override techniques that were previously required for custom observability.

## The Problem with Monkey-Patching

Before the event system, intercepting DSPy events required complex approaches:

### ❌ Old Approach: Complex Logger Backend Override

```ruby
# Required custom backend classes
class EventInterceptorBackend < Dry::Logger::Backends::Stream
  def call(entry)
    # Complex interception logic
    if handler = @event_handlers[entry[:event]]
      handler.call(entry)
    end
    super
  end
end

# Fragile configuration
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy) do |logger|
    logger.add_backend(EventInterceptorBackend.new(stream: "log/production.log"))
  end
end
## ✅ New Approach: Event System

The new event system provides clean, simple observability without monkey-patching:

### Token Cost Tracking

```ruby
# From spec/support/event_subscriber_examples.rb
class TokenCostTracker < DSPy::Events::BaseSubscriber
  def initialize
    super
    @costs = Hash.new(0.0)
    subscribe
  end
  
  def subscribe
    add_subscription('llm.*') do |event_name, attributes|
      model = attributes['gen_ai.request.model']
      input_tokens = attributes['gen_ai.usage.prompt_tokens'] || 0
      output_tokens = attributes['gen_ai.usage.completion_tokens'] || 0
      
      cost = calculate_cost(model, input_tokens, output_tokens)
      @costs[model] += cost
      
      puts "#{model}: $#{cost.round(4)} (total: $#{@costs[model].round(2)})"
    end
  end
end

tracker = TokenCostTracker.new
# Automatically tracks all LLM costs - no configuration needed
```

### Rate Limiting

```ruby
# Simple, testable rate limiter
class RateLimiter < DSPy::Events::BaseSubscriber
  def initialize(limit: 100)
    super
    @requests = Hash.new(0)
    @limit = limit
    subscribe
  end
  
  def subscribe
    add_subscription('llm.generate') do |event_name, attributes|
      model = attributes['gen_ai.request.model']
      key = "#{model}:#{Time.now.to_i / 60}"
      
      @requests[key] += 1
      if @requests[key] > @limit
        DSPy.event('rate_limit.exceeded', model: model, count: @requests[key])
      end
    end
  end
end
```

### Audit Logging

```ruby
class AuditLogger < DSPy::Events::BaseSubscriber
  def subscribe
    add_subscription('llm.*') do |event_name, attributes|
      AuditLog.create!(
        event: event_name,
        model: attributes['gen_ai.request.model'],
        tokens: attributes['gen_ai.usage.total_tokens'],
        user_id: Current.user&.id,
        timestamp: Time.current
      )
    end
  end
end
```

## Why the Event System is Better

### ✅ Advantages

1. **Discoverable**: `DSPy.events.subscribe()` is explicit and searchable
2. **Testable**: Easy to test subscribers in isolation  
3. **Type Safe**: Sorbet T::Struct validation for event structures
4. **Thread Safe**: Built-in concurrency protection
5. **Error Isolated**: Failing listeners don't break others
6. **No Dependencies**: Doesn't require custom backend classes

### ❌ Problems with Monkey-Patching

1. **Hidden behavior**: Prepend modules are invisible in code
2. **Testing complexity**: Hard to test interceptors in isolation  
3. **Fragility**: Breaks when internal APIs change
4. **Performance overhead**: Every call goes through override chain
5. **Debugging difficulty**: Stack traces become confusing

## Migration Guide

### Before (Complex)
```ruby
# Required monkey-patching
module ContextInterceptor
  def with_span(operation:, **attributes)
    # Complex interception logic
    super  
  end
end
DSPy::Context.singleton_class.prepend(ContextInterceptor)
```

### After (Simple)  
```ruby
# Clean subscriber pattern
class MyTracker < DSPy::Events::BaseSubscriber
  def subscribe
    add_subscription('llm.*') { |name, attrs| handle_event(attrs) }
  end
end

tracker = MyTracker.new
```

## When to Use Each Approach

### Use Event System (Recommended)
- Token tracking and budget management
- Custom analytics and reporting  
- Integration with external services
- Performance monitoring
- User-facing observability features

### Use Monkey-Patching (Legacy)
- Deep system modifications (not recommended)
- Intercepting internal APIs (brittle)
- When event system doesn't provide needed hooks

## Examples in Source

See working implementations:
- `spec/unit/event_system_spec.rb` - Thread safety tests
- `spec/unit/event_subscribers_spec.rb` - Subscriber patterns
- `spec/support/event_subscriber_examples.rb` - Complete implementations
- `examples/event_system_demo.rb` - Live demonstration