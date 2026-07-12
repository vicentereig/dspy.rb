---
layout: blog
title: "DSPy.rb, Async, and Sidekiq: Concurrency Inside a Job"
description: "How to run independent DSPy.rb calls concurrently inside one Sidekiq job, with explicit limits and accurate worker-thread semantics."
date: 2025-09-10
author: "Vicente Reig"
category: "Architecture"
reading_time: "8 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/dspy-async-sidekiq-integration/"
image: /images/og/dspy-async-sidekiq-integration.png
tags: ["sidekiq", "async", "concurrency", "background-jobs", "performance"]
---

Sidekiq and Async solve different scheduling problems. Sidekiq runs jobs on a pool of native threads. Async can coordinate several independent operations inside one of those jobs.

An LLM call that waits inside an Async task does not release the Sidekiq thread to execute another job. The job still owns that worker thread until `perform` returns. The useful case is narrower: one job has several independent provider calls and wants their waits to overlap.

## The execution boundary in DSPy.rb

`DSPy::LM#chat` enters a `Sync` block and forks the current DSPy context before calling the adapter:

```ruby
def chat(inference_module, input_values, &block)
  parent_context = DSPy::Context.current

  Sync do
    Fiber[:dspy_context] = DSPy::Context.fork_context(parent_context)
    chat_with_strategy(inference_module, input_values, &block)
  end
end
```

This gives the call an Async task context and isolates mutable trace stacks. It does not create sibling predictions, and it does not prove that every provider SDK yields during network I/O.

## Prefer one job per independent unit

When documents are independent and job overhead is acceptable, enqueue one job per document. Sidekiq already supplies concurrency, retries, queue controls, and operational visibility at that boundary:

```ruby
class AnalyzeDocumentJob
  include Sidekiq::Job

  def perform(document_id)
    document = Document.find(document_id)
    result = analyzer.call(content: document.content)
    document.update!(analysis: result.analysis)
  end

  private

  def analyzer
    @analyzer ||= DSPy::Predict.new(DocumentAnalysis)
  end
end

document_ids.each { |id| AnalyzeDocumentJob.perform_async(id) }
```

This keeps failure and retry scope small. One provider timeout does not require replaying an entire batch.

The [production guide](/dspy.rb/production/) covers the broader deployment boundary. Use [observability](/dspy.rb/production/observability/) to inspect module and provider spans; it does not replace Sidekiq's job and retry metrics.

## Concurrent calls inside one job

Sometimes one job owns one record but needs several independent analyses before it can commit the result. Create the sibling tasks explicitly and wait for all of them:

```ruby
require 'async'
require 'async/barrier'

class DocumentEnrichmentJob
  include Sidekiq::Job

  def perform(document_id)
    document = Document.find(document_id)

    results = Sync do
      barrier = Async::Barrier.new
      tasks = {
        summary: barrier.async { summarizer.call(content: document.content) },
        topics: barrier.async { topic_classifier.call(content: document.content) },
        sentiment: barrier.async { sentiment_analyzer.call(content: document.content) }
      }

      barrier.wait
      tasks.transform_values(&:result)
    end

    document.update!(
      summary: results[:summary].summary,
      topics: results[:topics].topics,
      sentiment: results[:sentiment].sentiment
    )
  end
end
```

The three calls can overlap only if their transports cooperate with Ruby's fiber scheduler. The Sidekiq thread remains occupied for the duration of the job.

Do not use this shape when one result feeds the next. Keep dependent module calls sequential so the control flow and failure point remain explicit.

## Bound concurrency

A Sidekiq process may already run many jobs at once. If every job launches a large number of provider calls, the effective concurrency is approximately Sidekiq concurrency multiplied by each job's child-task count. That can exhaust HTTP connections or provider rate limits quickly.

Put a fixed bound around fan-out. The exact primitive depends on the Async version and application architecture, but the limit should be deliberate and lower than the provider and connection-pool ceilings.

```ruby
MAX_CALLS_PER_JOB = 3

documents.each_slice(MAX_CALLS_PER_JOB) do |slice|
  Sync do
    barrier = Async::Barrier.new
    slice.each do |document|
      barrier.async { analyzer.call(content: document.content) }
    end
    barrier.wait
  end
end
```

This batches work; it is not a global limiter across Sidekiq threads or processes. Use a shared rate limiter when the provider quota is global.

## Failure and retry boundaries

DSPy.rb v0.28.0 removed its former core retry strategy. Current behavior has several layers:

- Sidekiq retries the whole job according to its job policy.
- Provider SDK configuration may retry transport failures.
- Your job decides whether a failed child task invalidates the whole result.
- A few adapters have narrow compatibility fallbacks for rejected structured-output parameters; those are not general prediction retries.

Avoid retrying the same failure independently at every layer. Multiplicative retries are expensive and make elapsed time difficult to predict.

For partial results, collect outcomes explicitly and decide which fields are required before updating the record. For all-or-nothing work, let the task failure abort the job and make the database write idempotent.

## Measure the job, not an isolated sleep

Compare complete job runs through the deployed provider adapter. Record:

- Job wall-clock time.
- Provider requests and rate-limit responses.
- Sidekiq retries.
- Connection-pool saturation.
- Partial or failed child tasks.

A three-call example can approach the duration of its slowest call when waits overlap, but `3 x 3 seconds` versus `3 seconds` is only an illustration. It is not a DSPy.rb performance guarantee.

Use Sidekiq concurrency for independent jobs. Use Async inside a job only when that job contains independent waits and the extra failure and rate-limit complexity earns its place.
