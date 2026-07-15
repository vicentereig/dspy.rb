---
layout: docs
name: Event System
description: Emit, observe, and react to runtime telemetry in DSPy.rb
date: 2025-10-26 00:00:00 +0000
last_modified_at: 2025-10-26 00:00:00 +0000
---
# Event System

DSPy.rb provides a structured event bus for module instrumentation and integrations. Emit events, subscribe globally or by module scope, and unsubscribe when the listener's lifetime ends.

## Two Subscription Patterns

Choose a subscription scope by listener lifetime:

### Pattern 1: Module-Scoped Subscriptions

Use the `subscribe` DSL inside your modules. Subscriptions automatically scope to the module instance and its descendants:

```ruby
class MyAgent < DSPy::Module
  subscribe 'lm.tokens', :track_tokens, scope: :descendants

  def track_tokens(_event, attrs)
    @total_tokens += attrs.fetch(:total_tokens, 0)
  end
end
```

**When to use:** Modules with internal state or any listener whose lifetime should match a module instance.

### Pattern 2: Global Subscriptions (For Observability/Integrations)

Use `DSPy.events.subscribe` directly for cross-cutting concerns:

```ruby
subscription_id = DSPy.events.subscribe('score.create') do |event, attrs|
  Langfuse.export_score(attrs)
end
```

**When to use:** Observability exporters (Langfuse, Datadog), centralized logging, metrics collection, or any cross-cutting concern that spans multiple modules.

## Emitting Events

Call `DSPy.event` for application events that subscribers should receive:

```ruby
DSPy.event('chain_of_thought.reasoning_complete', {
  question: question,
  reasoning_steps: reasoning.count("\n") + 1
})
```

Event naming, attributes, and types:

- Event names are strings with dot-separated namespaces (`llm.generate`, `react.iteration_complete`, etc.).
- Attributes must be JSON-serializable. DSPy automatically merges context (trace ID, module stack) and emits OpenTelemetry spans unless the event is marked internal.
- Typed events (`DSPy::Events::LLMEvent`, `DSPy::Events::OptimizationEvent`, etc.) can be passed instead of raw strings; the event bus extracts their attributes and spans for you.

## Global Listeners

To receive every event, subscribe directly to the registry:

```ruby
DSPy.events.subscribe('*') do |event_name, attrs|
  puts "[#{event_name}] tokens=#{attrs[:total_tokens]}"
end
```

Wildcard and teardown rules:

- Wildcards (`llm.*`) are supported. An exact string listens to one event.
- `DSPy.events.unsubscribe(id)` removes a listener by subscription ID.
- Use `DSPy.events.clear_listeners` in tests to avoid cross-contamination.

For custom tracking, create a class that manages subscriptions:

```ruby
class TokenBudgetTracker
  def initialize(budget:)
    @budget = budget
    @usage = 0
    @subscriptions = []
    subscribe
  end

  def subscribe
    @subscriptions << DSPy.events.subscribe('lm.tokens') do |_event, attrs|
      @usage += attrs.fetch(:total_tokens, 0)
      warn("Budget hit") if @usage >= @budget
    end
  end

  def unsubscribe
    @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
    @subscriptions.clear
  end
end
```

Call `tracker.unsubscribe` when you are done.

## Module-Scoped Subscribers

Every `DSPy::Module` can declare listeners scoped to its instance and, by default, descendants invoked inside it:

```ruby
class OutlineSignature < DSPy::Signature
  description "Identify report sections"
  input  { const :question, String }
  output { const :sections, T::Array[String] }
end

class SectionWriterSignature < DSPy::Signature
  description "Write a section paragraph"
  input do
    const :question, String
    const :section_title, String
  end
  output { const :paragraph, String }
end

class ResearchReport < DSPy::Module
  subscribe 'lm.tokens', :track_tokens # default scope: descendants

  def initialize
    super
    @outliner = DSPy::Predict.new(OutlineSignature)
    @section_writer = DSPy::Predict.new(SectionWriterSignature)
    @token_count = 0
  end

  def forward(question:)
    outline = @outliner.call(question: question)
    outline.sections.map do |section_title|
      draft = @section_writer.call(
        question: question,
        section_title: section_title
      )

      { title: section_title, body: draft.paragraph }
    end
  end

  def track_tokens(_event, attrs)
    @token_count += attrs.fetch(:total_tokens, 0)
  end
end
```

Because the `subscribe` call does not specify a scope, it listens to events emitted by the `ResearchReport` module **and** both nested `Predict` instances. Use `scope: DSPy::Module::SubcriptionScope::SelfOnly` to ignore descendants, for example when logging only the parent module's own `search.result` events.

Scope and metadata rules:

- `DSPy::Module::SubcriptionScope::Descendants` is the default and covers the module plus nested modules. `SubcriptionScope::SelfOnly` restricts delivery to the module instance itself.
- Instance methods `registered_module_subscriptions` and `unsubscribe_module_events` allow inspection and teardown (useful in long-running services or tests).
- DSPy merges module metadata into every event (`module_path`, `module_leaf`, `module_scope.ancestry_token`, etc.). Listeners can filter manually by inspecting those keys.

## Module Stack Metadata

The context layer tracks a stack of modules whenever `DSPy::Module#forward` runs. Each entry contains:

- `id`: stable UUID per instance (safe across forks)
- `class`: module class name
- `label`: optional label (set via `module_scope_label=` or derived from named predictors)

Events include:

```ruby
{
  module_path: [
    {id: "root_uuid", class: "DeepSearch", label: nil},
    {id: "planner_uuid", class: "DSPy::Predict", label: "planner"}
  ],
  module_root: {...},
  module_leaf: {...},
  module_scope: {
    ancestry_token: "root_uuid>planner_uuid",
    depth: 2
  }
}
```

Use this metadata to power Langfuse filters, scoped metrics, or custom routing.

## Choose Listener Ownership and Teardown

- **Global observability:** Mount a single `'*'` listener that forwards events to your logging or metrics pipeline. Use module metadata to fan out to feature-specific sinks.
- **Module-owned instrumentation:** Use the per-module `subscribe` DSL so subscriptions live with the logic they instrument. Call `unsubscribe_module_events` in teardown hooks, such as when a job finishes, to prevent leaks.
- **Testing:** Clear global listeners in `before`/`after` blocks and assert on collected events. For module-scoped specs, instantiate the module and inspect `registered_module_subscriptions`.
- **Versioning:** These APIs ship in the main `dspy` gem. Upgrading the gem automatically brings the event bus and module listener features into every sub-gem (`dspy-code_act`, `dspy-o11y`, etc.) because they depend on the core runtime.

The event bus separates module behavior from token accounting, tracing exports, and custom domain instrumentation.
