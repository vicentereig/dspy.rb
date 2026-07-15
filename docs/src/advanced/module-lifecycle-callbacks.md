---
layout: docs
title: Module Lifecycle Callbacks
name: Module Lifecycle Callbacks
description: Add ordered before, around, and after behavior to a DSPy.rb module call.
date: 2026-07-15 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
# Module Lifecycle Callbacks

Add one cross-cutting lifecycle around a module's `forward` call without changing the task signature.

## Prerequisites

Implement a module with `forward` as shown in [Modules](/dspy.rb/core-concepts/modules/). Runtime model selection belongs to [Module Runtime Context](/dspy.rb/advanced/module-runtime-context/), not to callbacks.

## Define the Callback Lifecycle

- `before` runs before `forward`.
- `around` wraps `forward` and must `yield` to execute it.
- `after` runs after a successful wrapped call.

Callbacks of the same type run in registration order. Inherited parent callbacks precede child callbacks. A combined call runs `before`, the pre-yield half of `around`, `forward`, the post-yield half of `around`, then `after`.

## Wrap a Module Call

This example is complete and network-free: callbacks wrap a deterministic `forward` method, making their order and failure behavior directly observable.

<!-- module-lifecycle-callbacks-program -->
```ruby
require 'dspy'

class NormalizedQuestion < DSPy::Module
  attr_reader :events

  before :record_start
  around :record_call
  after :record_finish

  def initialize
    super
    @events = []
  end

  def forward(question:)
    @events << :forward
    raise ArgumentError, "question cannot be blank" if question.strip.empty?

    question.strip
  end

  private

  def record_start
    @events << :before
  end

  def record_call
    @events << :around_before
    result = yield
    @events << :around_after
    result
  rescue StandardError
    @events << :around_error
    raise
  end

  def record_finish
    @events << :after
  end
end

normalizer = NormalizedQuestion.new
result = normalizer.call(question: "  What is a typed module?  ")
puts result
puts normalizer.events.join(" -> ")
```

A successful call prints the normalized question and `before -> around_before -> forward -> around_after -> after`. A blank question records `around_error`, re-raises `ArgumentError`, and does not run `after`. An `around` callback that omits `yield` prevents `forward` from running. Keep mutable callback state per call when a module instance may be shared concurrently.

## Choose the Supported Integration

- Subscribe to typed runtime signals through [Events](/dspy.rb/core-concepts/events/) when the concern does not need to wrap execution.
- Inspect traces and exporter behavior in [Observability](/dspy.rb/production/observability/).
- Use [Observability Interception](/dspy.rb/advanced/observability-interception/) before considering a monkey patch.
