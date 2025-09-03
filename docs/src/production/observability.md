---
layout: docs
name: Observability
description: Monitor and trace your DSPy applications in production
breadcrumb:
- name: Production
  url: "/production/"
- name: Observability
  url: "/production/observability/"
prev:
  name: Storage System
  url: "/production/storage/"
next:
  name: Registry
  url: "/production/registry/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-09 00:00:00 +0000
---
# Observability

DSPy.rb provides an event-driven observability system based on OpenTelemetry. The system eliminates complex monkey-patching while providing powerful, extensible observability features.

## Overview

The observability system offers:
- **Event System**: Simple `DSPy.event()` API for structured event emission
- **Pluggable Listeners**: Subscribe to events with pattern matching
- **OpenTelemetry Integration**: Automatic span creation with semantic conventions  
- **Langfuse Export**: Zero-config export to Langfuse via OpenTelemetry
- **Type Safety**: Sorbet T::Struct event validation
- **Thread Safe**: Concurrent access with mutex protection
- **Zero Breaking Changes**: All existing `DSPy.log()` calls work unchanged

## Architecture

The event system is built around three core components:

```ruby
# Event emission
DSPy.event('llm.generate', provider: 'openai', tokens: 150)

# Event listening  
DSPy.events.subscribe('llm.*') { |name, attrs| track_usage(attrs) }

# Custom subscribers
class MyTracker < DSPy::Events::BaseSubscriber
  def subscribe
    add_subscription('optimization.*') { |name, attrs| handle_trial(attrs) }
  end
end
```

## Quick Start

### Basic Event Emission

```ruby
# Emit events with attributes
DSPy.event('llm.response', {
  provider: 'openai',
  model: 'gpt-4', 
  tokens: 150,
  duration_ms: 1200
})

# Events automatically create OpenTelemetry spans and log entries
```

### Event Listeners

```ruby
# Subscribe to specific events
DSPy.events.subscribe('llm.response') do |event_name, attributes|
  puts "LLM call: #{attributes[:model]} used #{attributes[:tokens]} tokens"
end

# Pattern matching with wildcards
DSPy.events.subscribe('llm.*') do |event_name, attributes|
  track_llm_usage(attributes)
end

# Unsubscribe when done
subscription_id = DSPy.events.subscribe('test.*') { |name, attrs| }
DSPy.events.unsubscribe(subscription_id)
```

### Custom Subscribers

```ruby
class TokenTracker < DSPy::Events::BaseSubscriber
  attr_reader :total_tokens
  
  def initialize
    super
    @total_tokens = 0
    subscribe
  end
  
  def subscribe
    add_subscription('llm.*') do |event_name, attributes|
      tokens = attributes['gen_ai.usage.total_tokens'] || 0
      @total_tokens += tokens
    end
  end
end

tracker = TokenTracker.new
# Now automatically tracks token usage from any LLM events
```

## Built-in Events

DSPy modules automatically emit events following OpenTelemetry semantic conventions:

### LLM Events

```ruby
# Emitted automatically by DSPy::LM (lib/dspy/lm.rb:254)
DSPy.event('lm.tokens', {
  'gen_ai.system' => 'openai',
  'gen_ai.request.model' => 'gpt-4', 
  'gen_ai.usage.prompt_tokens' => 150,
  'gen_ai.usage.completion_tokens' => 50,
  'gen_ai.usage.total_tokens' => 200,
  'dspy.signature' => 'QuestionAnswering'
})
```

### Module Events  

```ruby
# ChainOfThought reasoning (lib/dspy/chain_of_thought.rb:176)
DSPy.event('chain_of_thought.reasoning_complete', {
  'dspy.signature' => 'QuestionAnswering',
  'cot.reasoning_steps' => 3,
  'cot.reasoning_length' => 245,
  'cot.has_reasoning' => true
})

# ReAct iterations (lib/dspy/re_act.rb:422)  
DSPy.event('react.iteration_complete', {
  iteration: 2,
  thought: 'I need to search for information',
  action: 'search',
  observation: 'Found relevant results'
})

# CodeAct code execution (lib/dspy/code_act.rb:358)
DSPy.event('codeact.iteration_complete', {
  iteration: 1,
  code_executed: 'puts "Hello World"',
  execution_result: 'Hello World'
})
```

## Type-Safe Events

Create structured events with validation:

```ruby
# Type-safe LLM event
llm_event = DSPy::Events::LLMEvent.new(
  name: 'llm.generate',
  provider: 'openai',
  model: 'gpt-4',
  usage: DSPy::Events::TokenUsage.new(
    prompt_tokens: 150,
    completion_tokens: 75
  ),
  duration_ms: 1250
)

DSPy.event(llm_event)
# Automatically includes OpenTelemetry semantic conventions
```

### Available Event Types

```ruby
# Basic event
DSPy::Events::Event.new(name: 'custom.event', attributes: { key: 'value' })

# Module execution event
DSPy::Events::ModuleEvent.new(
  name: 'module.forward', 
  module_name: 'ChainOfThought',
  signature_name: 'QuestionAnswering'
)

# Optimization event
DSPy::Events::OptimizationEvent.new(
  name: 'optimization.trial_complete',
  optimizer_name: 'MIPROv2',
  score: 0.85
)
```

## Common Patterns

### Token Budget Tracking

```ruby
# From spec/support/event_subscriber_examples.rb
class TokenBudgetTracker < DSPy::Events::BaseSubscriber
  attr_reader :total_tokens, :total_cost
  
  def initialize(budget_limit: 10000)
    super
    @budget_limit = budget_limit
    @total_tokens = 0
    @total_cost = 0.0
    subscribe
  end
  
  def subscribe
    add_subscription('llm.*') do |event_name, attributes|
      prompt_tokens = attributes['gen_ai.usage.prompt_tokens'] || 0
      completion_tokens = attributes['gen_ai.usage.completion_tokens'] || 0
      @total_tokens += prompt_tokens + completion_tokens
      
      # Calculate cost (example pricing)
      model = attributes['gen_ai.request.model']
      cost_per_1k = model == 'gpt-4' ? 0.03 : 0.002
      @total_cost += (@total_tokens / 1000.0) * cost_per_1k
    end
  end
  
  def budget_exceeded?
    @total_tokens > @budget_limit
  end
end

tracker = TokenBudgetTracker.new(budget_limit: 5000)
# Automatically tracks all LLM token usage
```

### Optimization Progress Tracking

```ruby
# From spec/unit/module_event_integration_spec.rb
class OptimizationTracker < DSPy::Events::BaseSubscriber
  attr_reader :trials, :best_score
  
  def initialize
    super
    @trials = []
    @best_score = nil
    subscribe
  end
  
  def subscribe
    add_subscription('optimization.*') do |event_name, attributes|
      case event_name
      when 'optimization.trial_complete'
        score = attributes[:score]
        @trials << { trial: attributes[:trial_number], score: score }
        @best_score = score if !@best_score || score > @best_score
      end
    end
  end
end

tracker = OptimizationTracker.new
# Automatically tracks MIPROv2, SimpleOptimizer, etc.
```

### Module Performance Tracking

```ruby
# From spec/unit/module_event_integration_spec.rb  
class ModulePerformanceTracker < DSPy::Events::BaseSubscriber
  attr_reader :module_stats
  
  def initialize
    super
    @module_stats = Hash.new { |h, k| 
      h[k] = { total_calls: 0, total_duration: 0, avg_duration: 0 } 
    }
    subscribe
  end
  
  def subscribe
    add_subscription('*.complete') do |event_name, attributes|
      module_name = event_name.split('.').first
      duration = attributes[:duration_ms] || 0
      
      stats = @module_stats[module_name]
      stats[:total_calls] += 1
      stats[:total_duration] += duration
      stats[:avg_duration] = stats[:total_duration] / stats[:total_calls].to_f
    end
  end
end

tracker = ModulePerformanceTracker.new
# Tracks ChainOfThought, ReAct, CodeAct performance
```

## Integration with External Systems

### Event Filtering and Routing

```ruby
# Route different events to different systems
class EventRouter < DSPy::Events::BaseSubscriber
  def initialize(datadog_client:, slack_webhook:)
    super
    @datadog = datadog_client
    @slack = slack_webhook
    subscribe
  end
  
  def subscribe
    # Send LLM events to Datadog for cost tracking
    add_subscription('llm.*') do |event_name, attributes|
      @datadog.increment('dspy.llm.requests', tags: [
        "provider:#{attributes['gen_ai.system']}",
        "model:#{attributes['gen_ai.request.model']}"
      ])
    end
    
    # Send optimization events to Slack
    add_subscription('optimization.trial_complete') do |event_name, attributes|
      if attributes[:score] > 0.9
        @slack.send("🎉 Trial #{attributes[:trial_number]} achieved #{attributes[:score]} score!")
      end
    end
  end
end
```

### Custom Analytics

```ruby
# From spec/unit/event_system_spec.rb (Thread and Fiber Safety tests)
class EventAnalytics < DSPy::Events::BaseSubscriber
  def initialize
    super
    @analytics = Concurrent::Hash.new
    subscribe
  end
  
  def subscribe
    add_subscription('*') do |event_name, attributes|
      # Thread-safe analytics collection
      category = event_name.split('.').first
      @analytics.compute(category) { |old_val| (old_val || 0) + 1 }
    end
  end
  
  def report
    @analytics.to_h
  end
end
```

## Backward Compatibility

All existing `DSPy.log()` calls automatically benefit from the event system:

```ruby
# Existing code (unchanged)
DSPy.log('chain_of_thought.reasoning_complete', {
  signature_name: 'QuestionAnswering', 
  reasoning_steps: 3
})

# Now automatically:
# ✅ Logs to stdout/file (same as before)
# ✅ Creates OpenTelemetry spans  
# ✅ Notifies event listeners
# ✅ Exports to Langfuse when configured
```

No code changes required - existing modules get enhanced observability automatically.

## Configuration

```ruby
DSPy.configure do |config|
  # Logger configuration (same as before)
  config.logger = Dry.Logger(:dspy, formatter: :json)
end

# Events work immediately - no additional setup needed
# Langfuse: Just set environment variables
# Custom subscribers: Create and they start working
```

## Best Practices

1. **Use Semantic Names**: Follow dot notation (`llm.generate`, `module.forward`)

2. **Clean Up Subscribers**: Always call `unsubscribe()` when done
   ```ruby
   tracker = MyTracker.new
   # ... use tracker
   tracker.unsubscribe  # Clean up listeners
   ```

3. **Handle Listener Errors**: Event system isolates failures
   ```ruby
   add_subscription('llm.*') do |name, attrs|
     risky_operation(attrs)
   rescue => e
     # Error logged automatically, other listeners continue
   end
   ```

4. **Use OpenTelemetry Conventions**: Follow semantic naming for LLM events
   ```ruby
   DSPy.event('llm.generate', {
     'gen_ai.system' => 'openai',           # Required
     'gen_ai.request.model' => 'gpt-4',     # Required  
     'gen_ai.usage.prompt_tokens' => 100    # Recommended
   })
   ```

5. **Pattern Matching**: Use wildcards for broad tracking
   ```ruby
   add_subscription('optimization.*')  # All optimization events
   add_subscription('llm.*')          # All LLM events
   add_subscription('*')              # All events (careful!)
   ```

## Troubleshooting

### Events Not Triggering Listeners

Check subscription patterns:
```ruby
# Make sure pattern matches event names
DSPy.events.subscribe('llm.*')    # Matches llm.generate, llm.stream
DSPy.events.subscribe('llm')      # Only matches exact 'llm'
```

### Memory Leaks with Subscribers

Always unsubscribe when done:
```ruby
class MyClass
  def initialize
    @tracker = TokenTracker.new
  end
  
  def cleanup
    @tracker.unsubscribe  # Important!
  end
end
```

### Thread Safety

Event system is thread-safe by design:
```ruby
# Multiple threads can safely emit events
threads = 10.times.map do |i|
  Thread.new { DSPy.event('test.event', thread_id: i) }
end
threads.each(&:join)
```

## Langfuse Integration (Zero Configuration)

DSPy.rb includes **zero-config Langfuse integration** via OpenTelemetry. Simply set your Langfuse environment variables and DSPy will automatically export spans to Langfuse alongside the normal logging.

### Setup

```bash
# Required environment variables
export LANGFUSE_PUBLIC_KEY=pk-lf-your-public-key
export LANGFUSE_SECRET_KEY=sk-lf-your-secret-key

# Optional: specify host (defaults to cloud.langfuse.com)
export LANGFUSE_HOST=https://cloud.langfuse.com  # or https://us.cloud.langfuse.com
```

### How It Works

When Langfuse environment variables are detected, DSPy automatically:

1. **Configures OpenTelemetry SDK** with OTLP exporter
2. **Creates dual output**: Both structured logs AND OpenTelemetry spans
3. **Exports to Langfuse** using proper authentication and endpoints
4. **Falls back gracefully** if OpenTelemetry gems are missing or configuration fails

### Example Output

With Langfuse configured, your DSPy applications will send traces like this:

**In your logs** (as usual):
```json
{
  "severity": "INFO",
  "time": "2025-08-08T22:02:57Z",
  "trace_id": "abc-123-def",
  "span_id": "span-456",
  "parent_span_id": "span-789",
  "operation": "ChainOfThought.forward",
  "dspy.module": "ChainOfThought",
  "event": "span.start"
}
```

**In Langfuse** (automatically):
```
Trace: abc-123-def
├─ ChainOfThought.forward [2000ms]
│  ├─ Module: ChainOfThought
│  └─ llm.generate [1000ms]
│     ├─ Model: gpt-4-0613
│     ├─ Temperature: 0.7
│     ├─ Tokens: 100 in / 50 out / 150 total
│     └─ Cost: $0.0021 (calculated by Langfuse)
```

### GenAI Semantic Conventions

DSPy automatically includes OpenTelemetry GenAI semantic conventions:

```ruby
# LLM operations automatically include:
{
  "gen_ai.system": "openai",
  "gen_ai.request.model": "gpt-4",
  "gen_ai.response.model": "gpt-4-0613",
  "gen_ai.usage.prompt_tokens": 100,
  "gen_ai.usage.completion_tokens": 50,
  "gen_ai.usage.total_tokens": 150
}
```

### Manual Configuration (Advanced)

For custom OpenTelemetry setups, you can disable auto-configuration and set up manually:

```ruby
# Disable auto-config by not setting Langfuse env vars
# Then configure OpenTelemetry yourself:

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure do |config|
  config.service_name = 'my-dspy-app'
  # Your custom configuration
end
```

### Dependencies

The Langfuse integration requires these gems (automatically included):
- `opentelemetry-sdk` (~> 1.8)
- `opentelemetry-exporter-otlp` (~> 0.30)

If these gems are not available, DSPy gracefully falls back to logging-only mode.

### Troubleshooting Langfuse Integration

**Spans not appearing in Langfuse:**
1. Verify environment variables are set correctly
2. Check Langfuse host/region (EU vs US)
3. Ensure network connectivity to Langfuse endpoints

**OpenTelemetry errors:**
1. Check that required gems are installed: `bundle install`
2. Look for observability error logs: `grep "observability.error" log/production.log`

**Authentication issues:**
1. Verify your public and secret keys are correct
2. Check that keys have proper permissions in Langfuse dashboard

## Summary

The DSPy.rb event system provides:

1. **Event API**: Simple `DSPy.event()` for structured emission
2. **Pluggable Listeners**: Subscribe to events with pattern matching
3. **OpenTelemetry Integration**: Automatic span creation and Langfuse export
4. **Type Safety**: Sorbet T::Struct event validation
5. **Backward Compatibility**: Existing `DSPy.log()` calls enhanced automatically

Key benefits:
- **Zero breaking changes**: All existing code works unchanged
- **Clean API**: Rails-like event system developers expect  
- **Extensible**: Easy to add custom observability providers
- **Type safe**: Structured events with validation
- **Thread safe**: Production-ready concurrent access
- **No dependencies**: Uses existing OpenTelemetry gems

The system eliminates complex monkey-patching while providing powerful observability features. See `examples/event_system_demo.rb` for hands-on demonstration.