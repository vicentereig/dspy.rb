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
- **Langfuse Export**: Zero-config export to Langfuse via OpenTelemetry (requires environment variables)
- **Type Safety**: Sorbet T::Struct event validation
- **Non-Blocking Exports**: Dedicated single-thread executor keeps telemetry off hot paths
- **Zero Breaking Changes**: All existing `DSPy.log()` calls work unchanged

## Installation

Add the observability gems alongside `dspy`:

```ruby
gem 'dspy'
gem 'dspy-o11y'           # core spans + helpers
gem 'dspy-o11y-langfuse'  # Langfuse/OpenTelemetry adapter (optional)
```

When hacking inside this monorepo, run `DSPY_WITH_O11Y=1 DSPY_WITH_O11Y_LANGFUSE=1 bundle install` to pull in the sibling gems.

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

### Dedicated Export Worker

Telemetry export happens on a `Concurrent::SingleThreadExecutor`, so your LLM workflows never compete with OTLP networking. The queue buffers spans as they finish, and the dedicated worker:

- Drains spans in batches based on configurable thresholds
- Applies exponential backoff on failures without blocking request threads
- Shuts down cleanly during process exit while flushing remaining spans

This design keeps observability reliable while ensuring DSPy.rb stays out of your LLMs' way.

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

## Observation Types

DSPy.rb uses Langfuse's semantic observation types to classify spans correctly in observability systems. These types provide meaningful categorization for different kinds of operations:

### Observation Type Classification

```ruby
# DSPy automatically selects appropriate observation types based on the module:

module_class = DSPy::ChainOfThought
observation_type = DSPy::ObservationType.for_module_class(module_class)
# => DSPy::ObservationType::Chain

# Available observation types:
DSPy::ObservationType::Generation  # Direct LLM calls
DSPy::ObservationType::Agent      # ReAct (core) and CodeAct (dspy-code_act) agents
DSPy::ObservationType::Tool       # Tool invocations  
DSPy::ObservationType::Chain      # ChainOfThought reasoning
DSPy::ObservationType::Retriever  # Memory/document search
DSPy::ObservationType::Embedding  # Embedding generation
DSPy::ObservationType::Evaluator  # Evaluation modules
DSPy::ObservationType::Span       # Generic operations
DSPy::ObservationType::Event      # Event emissions
```

### When to Emit Each Type

**Generation** (`generation`):
- Direct LLM API calls (OpenAI, Anthropic, etc.)
- Raw prompt-response interactions
- Core inference operations

```ruby
# Automatically used for:
lm = DSPy::LM.new('openai/gpt-4', api_key: ENV['OPENAI_API_KEY'])
lm.raw_chat([
  { role: 'user', content: 'What is 2+2?' }
])
# Creates span with langfuse.observation.type = 'generation'
```

**Agent** (`agent`):
- Multi-step reasoning agents (ReAct core, CodeAct via dspy-code_act)
- Iterative decision-making processes
- Tool-using autonomous agents

```ruby
# Automatically used for:
DSPy::ReAct.new(signature, tools: [calculator]).forward(question: "Calculate 15 * 23")
# Creates spans with langfuse.observation.type = 'agent'
```

**Tool** (`tool`):
- External tool invocations
- Function calls within agents
- API integrations

```ruby
# Automatically used for:
# Tool calls within ReAct agents get langfuse.observation.type = 'tool'
```

**Chain** (`chain`):
- Sequential reasoning operations
- ChainOfThought modules
- Multi-step logical processes

```ruby
# Automatically used for:
DSPy::ChainOfThought.new(signature).forward(question: "Explain gravity")
# Creates spans with langfuse.observation.type = 'chain'
```

**Retriever** (`retriever`):
- Memory/document search operations
- RAG retrieval steps
- Similarity matching

```ruby
# Automatically used for:
memory_manager = DSPy::Memory::MemoryManager.new
memory_manager.search_memories("find documents about Ruby")
# Creates spans with langfuse.observation.type = 'retriever'
```

**Embedding** (`embedding`):
- Text embedding generation
- Vector space operations
- Semantic encoding

```ruby
# Automatically used for:
embedding_engine = DSPy::Memory::LocalEmbeddingEngine.new
embedding_engine.embed("Convert this text to vectors")
# Creates spans with langfuse.observation.type = 'embedding'
```

### Custom Observation Types

For custom modules, specify observation types manually:

```ruby
class CustomModule < DSPy::Module
  def forward_untyped(**input_values)
    DSPy::Context.with_span(
      operation: 'custom.process',
      **DSPy::ObservationType::Evaluator.langfuse_attributes,  # Use evaluator type
      'custom.attribute' => 'value'
    ) do |span|
      # Your custom logic
      result
    end
  end
end
```

## Built-in Events

DSPy modules automatically emit events following OpenTelemetry semantic conventions:

### LLM Events

```ruby
# Emitted automatically by DSPy::LM (lib/dspy/lm.rb:300)
DSPy.event('lm.tokens', {
  'gen_ai.system' => 'openai',
  'gen_ai.request.model' => 'gpt-4', 
  input_tokens: 150,
  output_tokens: 50,
  total_tokens: 200,
  'dspy.signature' => 'QuestionAnswering',
  request_id: 'abc123def',  # If available
  duration: 1.25            # Seconds, if available
})
```

### Module Events  

```ruby
# ChainOfThought reasoning (lib/dspy/chain_of_thought.rb:199)
DSPy.event('chain_of_thought.reasoning_complete', {
  'dspy.signature' => 'QuestionAnswering',
  'cot.reasoning_steps' => 3,
  'cot.reasoning_length' => 245,
  'cot.has_reasoning' => true
})

# ReAct iterations (lib/dspy/re_act.rb:424)  
DSPy.event('react.iteration_complete', {
  iteration: 2,
  thought: 'I need to search for information',
  action: 'search',
  observation: 'Found relevant results'
})

# CodeAct code execution (see dspy-code_act gem)
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
# Automatically tracks DSPy teleprompters like MIPROv2
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
# Tracks ChainOfThought, ReAct, CodeAct performance (CodeAct requires dspy-code_act)
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

**Note**: Integration requires the `opentelemetry-sdk` and `opentelemetry-exporter-otlp` gems to be available and proper network connectivity to your Langfuse instance.

**🆕 Enhanced in v0.25.0**: Comprehensive span reporting improvements including proper input/output capture, hierarchical nesting, accurate timing, token usage tracking, and correct Langfuse observation types (`generation`, `chain`, `span`).

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

**Important**: Automatic configuration only occurs when required gems are available and environment variables are properly set. Always verify your setup in development before relying on it in production.

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
│  ├─ Observation Type: chain
│  └─ llm.generate [1000ms]
│     ├─ Model: gpt-4-0613
│     ├─ Observation Type: generation
│     ├─ Temperature: 0.7
│     ├─ Tokens: 100 in / 50 out / 150 total
│     └─ Cost: $0.0021 (calculated by Langfuse)
```

**Trace Examples by Observation Type**

Based on actual DSPy.rb implementation, here's what traces look like for different observation types:

**Generation Type (Direct LLM calls):**
```
Trace: gen-trace-123
├─ llm.generate [800ms]
│  ├─ Observation Type: generation
│  ├─ Provider: openai
│  ├─ Model: gpt-4
│  ├─ Response Model: gpt-4-0613
│  ├─ Input: [{"role":"user","content":"What is 2+2?"}]
│  ├─ Output: "4"
│  └─ Tokens: 10 in / 2 out / 12 total
```

**Chain Type (ChainOfThought reasoning):**
```
Trace: cot-trace-456
├─ ChainOfThought.forward [2100ms]
│  ├─ Observation Type: chain
│  ├─ Signature: QuestionAnswering
│  ├─ Input: {"question":"Explain gravity"}
│  ├─ Output: {"answer":"Gravity is...","reasoning":"..."}
│  └─ llm.generate [1800ms]
│     ├─ Observation Type: generation
│     ├─ Provider: openai
│     ├─ Model: gpt-4
│     └─ Tokens: 45 in / 120 out / 165 total
```

**Agent Type (ReAct multi-step reasoning):**
```
Trace: react-trace-789
├─ ReAct.forward [5200ms]
│  ├─ Observation Type: agent
│  ├─ Signature: AgentSignature
│  ├─ Tools: [calculator, search]
│  ├─ Iterations: 3
│  ├─ Final Answer: "The answer is 42"
│  ├─ llm.generate (Iteration 1) [1200ms]
│  │  ├─ Observation Type: generation
│  │  └─ Tokens: 80 in / 30 out / 110 total
│  ├─ Tool: calculator [50ms]
│  │  ├─ Observation Type: tool
│  │  ├─ Input: "15 * 23"
│  │  └─ Output: "345"
│  ├─ llm.generate (Iteration 2) [1100ms]
│  │  ├─ Observation Type: generation
│  │  └─ Tokens: 95 in / 25 out / 120 total
│  └─ llm.generate (Iteration 3) [900ms]
│     ├─ Observation Type: generation
│     └─ Tokens: 70 in / 20 out / 90 total
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
