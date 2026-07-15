---
layout: docs
name: Observability
description: Monitor and trace your DSPy applications in production
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-09 00:00:00 +0000
---
# Observability

DSPy.rb emits structured events and OpenTelemetry spans for modules, LM calls, tools, evaluation, and optimization. Subscribe to events for application metrics; install the optional Langfuse integration when you need span export there.

## Choose an Observability Boundary

The observability system offers:
- **Event system**: `DSPy.event()` emits a structured application event
- **Pluggable Listeners**: Subscribe to events with pattern matching
- **OpenTelemetry integration**: Instrumented operations create spans with semantic conventions
- **Langfuse Export**: Optional export through `dspy-o11y-langfuse` and OpenTelemetry configuration
- **Type Safety**: Sorbet T::Struct event validation
- **Asynchronous routine export**: A dedicated single-thread executor keeps routine telemetry export off request threads
- **Logging Compatibility**: Existing `DSPy.log()` calls continue to emit log events

## Installation

Add the observability gems alongside `dspy`:

```ruby
gem 'dspy'
gem 'dspy-o11y'           # core spans + helpers
gem 'dspy-o11y-langfuse'  # Langfuse/OpenTelemetry adapter (optional)
```

Check the [package and capability matrix](/dspy.rb/getting-started/packages/) for current overlap, loading, and support-status details before selecting observability gems.

When hacking inside this monorepo, run `DSPY_WITH_O11Y=1 DSPY_WITH_O11Y_LANGFUSE=1 bundle install` to pull in the sibling gems.

## Architecture

The event system is built around three core components:

```ruby
# Event emission
DSPy.event('llm.generate', provider: 'openai', tokens: 150)

# Event listening  
DSPy.events.subscribe('llm.*') { |name, attrs| track_usage(attrs) }

# Custom tracking (pattern for reusable subscribers)
class MyTracker
  def initialize
    @subscriptions = []
    @subscriptions << DSPy.events.subscribe('optimization.*') { |name, attrs| handle_trial(attrs) }
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
  end
end
```

### Dedicated Export Worker

Routine telemetry export runs on a `Concurrent::SingleThreadExecutor` instead of the thread that finishes the span. A bounded queue buffers completed spans, and the dedicated worker:

- Drains spans in batches based on configurable thresholds
- Applies exponential backoff on failures without blocking request threads
- Attempts to flush remaining spans during shutdown, up to the configured timeout

The worker still consumes process resources. A full queue drops its oldest span, exporter failures can exhaust their retries, and shutdown can time out before every span is sent. The asynchronous boundary removes routine OTLP export from the request thread; it does not guarantee delivery or make LLM calls non-blocking.

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

# Subscribers receive the event; enabled observability also creates a span.
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
class TokenTracker
  attr_reader :total_tokens

  def initialize
    @total_tokens = 0
    @subscriptions = []
    subscribe
  end

  def subscribe
    @subscriptions << DSPy.events.subscribe('llm.*') do |event_name, attributes|
      tokens = attributes['gen_ai.usage.total_tokens'] || 0
      @total_tokens += tokens
    end
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
  end
end

tracker = TokenTracker.new
# Now automatically tracks token usage from any LLM events
```

## Observation Types

DSPy.rb maps instrumented operations to Langfuse observation types so consumers can distinguish generations, agents, tools, chains, retrievers, and embeddings:

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
- Bounded tool-using agent loops

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
- Application-owned document search operations
- RAG retrieval steps
- Similarity matching

```ruby
class TracedRetriever
  def initialize(document_store)
    @document_store = document_store
  end

  def search(query, limit: 5)
    DSPy::Context.with_span(
      operation: 'retrieval.search',
      **DSPy::ObservationType::Retriever.langfuse_attributes,
      'retrieval.limit' => limit
    ) do
      @document_store.search(query, limit: limit)
    end
  end
end
```

DSPy.rb does not provide a document store. The wrapper instruments the retrieval client your application already owns.

**Embedding** (`embedding`):
- Text embedding generation
- Vector space operations
- Semantic encoding

```ruby
class TracedEmbeddingClient
  def initialize(client)
    @client = client
  end

  def embed(texts)
    DSPy::Context.with_span(
      operation: 'embedding.generate',
      **DSPy::ObservationType::Embedding.langfuse_attributes,
      'embedding.input_count' => texts.length
    ) do
      @client.embed(texts)
    end
  end
end
```

The same pattern works with any embedding client. Keep provider credentials and vector persistence in application code.

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

Instrumented DSPy module calls emit events with OpenTelemetry semantic attributes:

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
class TokenBudgetTracker
  attr_reader :total_tokens, :total_cost

  def initialize(budget_limit: 10000)
    @budget_limit = budget_limit
    @total_tokens = 0
    @total_cost = 0.0
    @subscriptions = []
    subscribe
  end

  def subscribe
    @subscriptions << DSPy.events.subscribe('llm.*') do |event_name, attributes|
      prompt_tokens = attributes['gen_ai.usage.prompt_tokens'] || 0
      completion_tokens = attributes['gen_ai.usage.completion_tokens'] || 0
      @total_tokens += prompt_tokens + completion_tokens

      # Calculate cost (example pricing)
      model = attributes['gen_ai.request.model']
      cost_per_1k = model == 'gpt-4' ? 0.03 : 0.002
      @total_cost += (@total_tokens / 1000.0) * cost_per_1k
    end
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
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
class OptimizationTracker
  attr_reader :trials, :best_score

  def initialize
    @trials = []
    @best_score = nil
    @subscriptions = []
    subscribe
  end

  def subscribe
    @subscriptions << DSPy.events.subscribe('optimization.*') do |event_name, attributes|
      case event_name
      when 'optimization.trial_complete'
        score = attributes[:score]
        @trials << { trial: attributes[:trial_number], score: score }
        @best_score = score if !@best_score || score > @best_score
      end
    end
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
  end
end

tracker = OptimizationTracker.new
# Automatically tracks DSPy teleprompters like MIPROv2
```

### Module Performance Tracking

```ruby
class ModulePerformanceTracker
  attr_reader :module_stats

  def initialize
    @module_stats = Hash.new { |h, k|
      h[k] = { total_calls: 0, total_duration: 0, avg_duration: 0 }
    }
    @subscriptions = []
    subscribe
  end

  def subscribe
    @subscriptions << DSPy.events.subscribe('*.complete') do |event_name, attributes|
      module_name = event_name.split('.').first
      duration = attributes[:duration_ms] || 0

      stats = @module_stats[module_name]
      stats[:total_calls] += 1
      stats[:total_duration] += duration
      stats[:avg_duration] = stats[:total_duration] / stats[:total_calls].to_f
    end
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
  end
end

tracker = ModulePerformanceTracker.new
# Tracks ChainOfThought, ReAct, CodeAct performance (CodeAct requires dspy-code_act)
```

## Integration with External Systems

### Event Filtering and Routing

```ruby
# Route different events to different systems
class EventRouter
  def initialize(datadog_client:, slack_webhook:)
    @datadog = datadog_client
    @slack = slack_webhook
    @subscriptions = []
    subscribe
  end

  def subscribe
    # Send LLM events to Datadog for cost tracking
    @subscriptions << DSPy.events.subscribe('llm.*') do |event_name, attributes|
      @datadog.increment('dspy.llm.requests', tags: [
        "provider:#{attributes['gen_ai.system']}",
        "model:#{attributes['gen_ai.request.model']}"
      ])
    end

    # Send optimization events to Slack
    @subscriptions << DSPy.events.subscribe('optimization.trial_complete') do |event_name, attributes|
      if attributes[:score] > 0.9
        @slack.send("Trial #{attributes[:trial_number]} achieved #{attributes[:score]} score!")
      end
    end
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
  end
end
```

### Custom Analytics

```ruby
class EventAnalytics
  def initialize
    @analytics = Concurrent::Hash.new
    @subscriptions = []
    subscribe
  end

  def subscribe
    @subscriptions << DSPy.events.subscribe('*') do |event_name, attributes|
      # Thread-safe analytics collection
      category = event_name.split('.').first
      @analytics.compute(category) { |old_val| (old_val || 0) + 1 }
    end
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
  end

  def report
    @analytics.to_h
  end
end
```

## Keep Logging Separate from Event Telemetry

`DSPy.log()` writes to the configured logger. It does not notify event subscribers or create telemetry spans. Use `DSPy.event()` when listeners or an OpenTelemetry exporter must receive the operation:

```ruby
DSPy.log('chain_of_thought.reasoning_complete', {
  signature_name: 'QuestionAnswering', 
  reasoning_steps: 3
})

DSPy.event('chain_of_thought.reasoning_complete', {
  signature_name: 'QuestionAnswering',
  reasoning_steps: 3
})
```

Existing `DSPy.log()` call sites continue to log without change. Moving a call site to `DSPy.event()` is an application decision because subscribers may add processing and side effects. Span export also requires the observability packages and exporter configuration.

## Configure Event and Export Behavior

```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :json)
end
```

Create and retain each custom subscriber explicitly, then unsubscribe it during shutdown. Langfuse export requires the packages, credentials, network access, and exporter lifecycle described below.

## Bound Subscribers and Event Data

1. **Use Semantic Names**: Follow dot notation (`llm.generate`, `module.forward`)

2. **Clean Up Subscribers**: Always call `unsubscribe()` when done
   ```ruby
   tracker = MyTracker.new
   # ... use tracker
   tracker.unsubscribe  # Clean up listeners
   ```

3. **Handle Listener Errors**: Event system isolates failures
   ```ruby
   DSPy.events.subscribe('llm.*') do |name, attrs|
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

## Configure Langfuse from Environment Variables {#langfuse-integration-zero-configuration}

With `dspy-o11y`, `dspy-o11y-langfuse`, the OpenTelemetry dependencies, and network access installed, setting the required Langfuse environment variables configures OTLP span export alongside logging.

The integration requires `opentelemetry-sdk`, `opentelemetry-exporter-otlp`, valid Langfuse credentials, and network connectivity to the configured instance.

**🆕 Enhanced in v0.25.0**: Comprehensive span reporting improvements including proper input/output capture, hierarchical nesting, accurate timing, token usage tracking, and correct Langfuse observation types (`generation`, `chain`, `span`).

### Set Langfuse Credentials

```bash
# Required environment variables
export LANGFUSE_PUBLIC_KEY=pk-lf-your-public-key
export LANGFUSE_SECRET_KEY=sk-lf-your-secret-key

# Optional: specify host (defaults to cloud.langfuse.com)
export LANGFUSE_HOST=https://cloud.langfuse.com  # or https://us.cloud.langfuse.com
```

### Telemetry Configuration

You can disable or tune async telemetry behavior with environment variables:

```bash
# Disable observability entirely
export DSPY_DISABLE_OBSERVABILITY=true

# Async processor tuning
export DSPY_TELEMETRY_QUEUE_SIZE=1000
export DSPY_TELEMETRY_EXPORT_INTERVAL=60.0
export DSPY_TELEMETRY_BATCH_SIZE=100
export DSPY_TELEMETRY_SHUTDOWN_TIMEOUT=10.0
```

#### Variable Reference

- `DSPY_DISABLE_OBSERVABILITY`:
  set to `true` to skip observability initialization and async export.
- `DSPY_TELEMETRY_QUEUE_SIZE` (default: `1000`):
  max spans buffered in memory before drops under pressure.
- `DSPY_TELEMETRY_EXPORT_INTERVAL` (default: `60.0`):
  timer interval (seconds) for periodic export.
- `DSPY_TELEMETRY_BATCH_SIZE` (default: `100`):
  number of spans per export batch and threshold for immediate flush.
- `DSPY_TELEMETRY_SHUTDOWN_TIMEOUT` (default: `10.0`):
  max seconds to wait for flush during shutdown.

#### Choose Settings by Process Lifecycle

- `CLI / short-lived process`:
  prioritize fast flushing and longer shutdown timeout.
  ```bash
  export DSPY_TELEMETRY_QUEUE_SIZE=2000
  export DSPY_TELEMETRY_EXPORT_INTERVAL=5.0
  export DSPY_TELEMETRY_BATCH_SIZE=50
  export DSPY_TELEMETRY_SHUTDOWN_TIMEOUT=30.0
  ```
- `Web API`:
  balanced latency and overhead.
  ```bash
  export DSPY_TELEMETRY_QUEUE_SIZE=1000
  export DSPY_TELEMETRY_EXPORT_INTERVAL=30.0
  export DSPY_TELEMETRY_BATCH_SIZE=100
  export DSPY_TELEMETRY_SHUTDOWN_TIMEOUT=10.0
  ```
- `Background jobs`:
  favor larger batches, then monitor queue drops, retries, and shutdown flushes.
  ```bash
  export DSPY_TELEMETRY_QUEUE_SIZE=5000
  export DSPY_TELEMETRY_EXPORT_INTERVAL=60.0
  export DSPY_TELEMETRY_BATCH_SIZE=500
  export DSPY_TELEMETRY_SHUTDOWN_TIMEOUT=60.0
  ```
- `Development / local`:
  disable observability to reduce noise.
  ```bash
  export DSPY_DISABLE_OBSERVABILITY=true
  ```

### Trace Environment-Driven Configuration

When the required Langfuse environment variables are present, initialization:

1. **Configures OpenTelemetry SDK** with OTLP exporter
2. **Creates dual output**: Both structured logs AND OpenTelemetry spans
3. **Exports to Langfuse** using proper authentication and endpoints
4. **Logs initialization failures** when a dependency or exporter configuration is unavailable

Environment-driven configuration runs only when the required gems and variables are present. Verify received spans and shutdown behavior in a non-production environment before depending on the exporter.

### Inspect Emitted Output

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

**In Langfuse** (when export is configured):
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

### Inspect GenAI Semantic Attributes

Instrumented LM operations include OpenTelemetry GenAI semantic attributes:

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

### Supply OpenTelemetry Configuration Directly

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

### Verify Export Dependencies

`dspy-o11y-langfuse` declares these export dependencies:
- `opentelemetry-sdk` (~> 1.8)
- `opentelemetry-exporter-otlp` (~> 0.30)

Without these gems, Langfuse span export is unavailable; DSPy logging remains separate.

### Troubleshooting Langfuse Integration

**Missing Langfuse spans:**
1. Verify environment variables are set correctly
2. Check Langfuse host/region (EU vs US)
3. Ensure network connectivity to Langfuse endpoints

**OpenTelemetry errors:**
1. Check that required gems are installed: `bundle install`
2. Look for observability error logs: `grep "observability.error" log/production.log`

**Authentication issues:**
1. Verify your public and secret keys are correct
2. Check that keys have proper permissions in Langfuse dashboard

<span id="score-reporting" data-canonical-route="/production/score-reporting/"></span>
<span id="basic-usage"></span><span id="score-data-types"></span><span id="built-in-evaluators"></span><span id="automatic-score-export-with-evals"></span><span id="async-langfuse-export"></span><span id="context-propagation"></span><span id="event-driven-architecture"></span>

## Report Evaluation Scores

Traces show what executed; they do not establish correctness. See [Score Reporting](/dspy.rb/production/score-reporting/) for the canonical `DSPy::Scores` types, evaluators, evaluation export, and bounded Langfuse exporter lifecycle.

## Protect Exported Data

See `examples/event_system_demo.rb` for event subscriptions and emitted attributes. Keep sensitive input and output data out of exported spans unless your retention and access policy permits it.
