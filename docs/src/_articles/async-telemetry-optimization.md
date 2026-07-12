---
layout: blog
title: "Async Execution and Retry Boundaries in DSPy.rb"
date: 2025-09-05
description: "How DSPy.rb uses Ruby's Async runtime, where automatic retries existed, and which concurrency decisions remain with the application"
author: "Vicente Reig"
tags: ["performance", "async", "concurrency", "reliability"]
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/async-telemetry-optimization/"
image: /images/og/async-telemetry-optimization.png
---

DSPy.rb v0.27 introduced an Async context for LLM calls and used `Async::Task.current.sleep()` for retry backoff. The wait yielded to sibling tasks in the same reactor instead of blocking that reactor.

That retry system no longer exists. DSPy.rb v0.28.0 removed core prediction and extraction retries while retaining the `Sync` wrapper around typed LLM calls. Current DSPy.rb executes a prediction once. Applications decide whether and how to retry it.

The version boundary matters because an Async context does not make a call concurrent by itself.

## What Async Scheduling Proves

Ruby's Async runtime can schedule another ready task when one task yields. This example puts two sibling tasks in one reactor:

```ruby
require "async"

events = []

Sync do |parent|
  waiting = parent.async do |task|
    events << :waiting_started
    task.sleep(0.1)
    events << :waiting_finished
  end

  ready = parent.async do
    events << :ready_ran
  end

  waiting.wait
  ready.wait
end

p events
# => [:waiting_started, :ready_ran, :waiting_finished]
```

The sleeping task yields, so its sibling runs before the sleep finishes. The example establishes cooperative scheduling inside one reactor. It makes no claim about LLM transport behavior.

In v0.27, DSPy.rb's retry backoff used the same yielding sleep. A failed prediction still waited for its next attempt, but sibling Async tasks could run during the backoff.

## What Current DSPy.rb Does

The predictor API did not change when core retries were removed:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o-mini")
end

class EmailClassifier < DSPy::Signature
  input { const :email_content, String }
  output { const :category, String }
end

classifier = DSPy::Predict.new(EmailClassifier)
result = classifier.call(email_content: "Meeting invitation...")
```

Current typed calls enter a `Sync` block before building the request, calling the adapter, and parsing the result:

```ruby
Sync do
  lm.chat(inference_module, input_values)
end
```

`Sync` supplies an Async task context. DSPy.rb does not create sibling tasks or schedule several predictions concurrently. The caller still waits until the prediction returns or raises.

An application that wants concurrent predictions must create and own that concurrency. Whether provider requests yield cooperatively then depends on the application's scheduler integration and the provider client's HTTP transport. Entering `Sync` alone does not prove non-blocking network I/O for every adapter.

## Retry Ownership After v0.28.0

DSPy.rb core no longer retries a failed prediction or cycles through extraction strategies. An application can wrap a prediction in its own retry policy and choose which failures deserve another request.

Provider SDKs may apply transport-level retries for network or rate-limit failures. Those policies belong to each SDK and its configuration; they are separate from the core retries removed in v0.28.0.

Some adapters also contain narrow compatibility fallbacks. For example, an adapter may retry a request without a structured-output parameter when a compatible endpoint rejects that parameter. These fallbacks handle a specific request shape. They are not a general prediction retry system.

DSPy.rb's JSON extraction strategies solve another problem: parsing and validating model output. They do not retry transport failures.

## Application Retry Example

The application can make retry behavior explicit at the call site. This pseudocode assumes the application maps provider-specific failures to `MyApp::RetryableProviderError`:

```ruby
attempts = 0

begin
  attempts += 1
  result = classifier.call(email_content: "Meeting invitation...")
rescue MyApp::RetryableProviderError
  raise if attempts >= 3

  sleep(0.5 * attempts)
  retry
end
```

Here, `MyApp::RetryableProviderError` is an application-defined boundary around the provider failures worth retrying. The exception mapping and delay policy depend on the provider and application. In an Async application, use an Async-aware delay inside the owning task so sibling tasks can run during backoff. Tests should control that policy rather than rely on DSPy.rb to retry.

## Background Jobs and Consoles

Background jobs use the same synchronous predictor API:

```ruby
# app/jobs/content_moderation_job.rb
class ContentModerationJob < ApplicationJob
  def perform(comment_id)
    comment = Comment.find(comment_id)

    result = DSPy::Predict.new(ToxicityDetector).call(
      text: comment.content
    )

    comment.update!(
      toxicity_score: result.score,
      needs_review: result.toxic?
    )
  end
end
```

The job waits for `result`. Other jobs progress according to the job runner's concurrency model, not because DSPy.rb schedules them.

An IRB or Rails console call also waits:

```ruby
analyzer = DSPy::Predict.new(ProductAnalyzer)

result = analyzer.call(description: "iPhone 15 Pro")
# Returns after the call completes or raises
```

## Provider Configuration

Async execution does not change provider configuration:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    "anthropic/claude-3-haiku",
    api_key: ENV["ANTHROPIC_API_KEY"]
  )
  # or
  config.lm = DSPy::LM.new(
    "ollama/llama2",
    api_key: ENV["OLLAMA_API_KEY"]
  )
end
```

## Performance Boundaries

A single prediction does not finish sooner because DSPy.rb enters `Sync`. Concurrency can improve throughput only when the application creates concurrent work and the relevant waits cooperate with its scheduler. Provider latency, connection limits, task count, and the surrounding server or job runner still set the result.

Measure that behavior in the deployment that owns the scheduler. DSPy.rb provides the task context for a typed call; it does not provide a general concurrency or retry policy.
