---
layout: docs
name: Event System
description: Emit, observe, and react to runtime telemetry in DSPy.rb
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Event System
  url: "/core-concepts/events/"
nav:
  prev:
    name: Predictors
    url: "/core-concepts/predictors/"
  next:
    name: Modules
    url: "/core-concepts/modules/"
date: 2025-10-26 00:00:00 +0000
last_modified_at: 2025-10-26 00:00:00 +0000
---
# Event System

DSPy.rb ships with a structured event bus so agents, tooling, and monitoring stacks can react to everything that happens at runtime. This page explains how to emit events, listen globally, scope listeners to specific modules, and cleanly tear everything down.

## Emitting Events

Use `DSPy.event` whenever something noteworthy happens:

```ruby
DSPy.event('chain_of_thought.reasoning_complete', {
  question: question,
  reasoning_steps: reasoning.count("\n") + 1
})
```

Key points:

- Event names are strings with dot-separated namespaces (`llm.generate`, `react.iteration_complete`, etc.).
- Attributes must be JSON-serializable. DSPy automatically merges context (trace ID, module stack) and emits OpenTelemetry spans unless the event is marked internal.
- Typed events (`DSPy::Events::LLMEvent`, `DSPy::Events::OptimizationEvent`, etc.) can be passed instead of raw strings; the event bus extracts their attributes and spans for you.

## Global Listeners

To react to every event (the question everyone asks), subscribe directly to the registry:

```ruby
DSPy.events.subscribe('*') do |event_name, attrs|
  puts "[#{event_name}] tokens=#{attrs[:total_tokens]}"
end
```

Notes:

- Wildcards (`llm.*`) are supported. An exact string listens to one event.
- `DSPy.events.unsubscribe(id)` removes a listener by subscription ID.
- `DSPy.events.clear_listeners` is handy in tests to avoid cross-contamination.

For richer lifecycle management inherit from `DSPy::Events::BaseSubscriber`:

```ruby
class TokenBudgetTracker < DSPy::Events::BaseSubscriber
  def initialize(budget:)
    super()
    @budget = budget
    @usage = 0
    subscribe
  end

  def subscribe
    add_subscription('lm.tokens') do |_event, attrs|
      @usage += attrs.fetch(:total_tokens, 0)
      warn("Budget hit") if @usage >= @budget
    end
  end
end
```

Call `subscriber.unsubscribe` when you are done.

## Module-Scoped Subscribers

Every `DSPy::Module` can now declare listeners that automatically scope to its instance (and optionally children):

```ruby
class DeepSearch < DSPy::Module
  subscribe 'llm.tokens', :meter_tokens            # descendants
  subscribe 'search.result', :self_only, scope: :self

  def meter_tokens(_event, attrs)
    @token_count += attrs.fetch(:total_tokens, 0)
  end

  def self_only(_event, attrs)
    # Only fires when DeepSearch itself emitted the event
    puts "Search result: #{attrs[:url]}"
  end
end
```

Details:

- `scope: :descendants` (default) fires for the module plus any nested modules invoked within it. `scope: :self` restricts delivery to events emitted by the module instance itself.
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

## Best Practices

- **Global observability?** Mount a single `'*'` listener that forwards events to your logging/metrics pipeline. Use module metadata to fan out to feature-specific sinks.
- **Tight modules?** Prefer the per-module `subscribe` DSL so subscriptions live with the logic they instrument. Call `unsubscribe_module_events` in teardown hooks (e.g., when a job finishes) to prevent leaks.
- **Testing:** Clear global listeners in `before`/`after` blocks and assert on collected events. For module-scoped specs, instantiate the module and inspect `registered_module_subscriptions`.
- **Versioning:** These APIs ship in the main `dspy` gem. Upgrading the gem automatically brings the event bus and module listener features into every sub-gem (`dspy-code_act`, `dspy-o11y`, etc.) because they depend on the core runtime.

With the event system in place you can observe anything—from token usage and Langfuse traces to custom domain signals—without scattering instrumentation across your agents.
