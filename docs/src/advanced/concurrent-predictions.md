---
layout: docs
title: Concurrent Predictions
name: Concurrent Predictions
description: Schedule independent DSPy.rb predictions with an explicit join, failure policy, and measured concurrency limit.
date: 2026-07-15 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
# Concurrent Predictions

Schedule a bounded set of independent predictor calls and collect every result. This is application-owned Ruby control flow; DSPy.rb does not create concurrent child tasks for a batch.

## Prerequisites

Define and call one predictor first in [Predictors](/dspy.rb/core-concepts/predictors/). Add `gem 'async', '~> 2.29'` to the application, then require `async` and `async/barrier`.

## Run, Join, and Preserve Failures

The complete program below uses the same OpenAI setup as Quick Start. Save it as `concurrent_predictions.rb` and run it with `bundle exec ruby concurrent_predictions.rb`.

<!-- concurrent-predictions-program -->
```ruby
require 'dspy'
require 'async'
require 'async/barrier'

class ClassifyText < DSPy::Signature
  description "Classify text sentiment"
  input { const :text, String }
  output { const :sentiment, String }
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV.fetch('OPENAI_API_KEY')
  )
end

ConcurrentPredictionResult = Data.define(:input, :prediction, :error)

class ConcurrentPredictionBatch
  MAX_BATCH_SIZE = 3

  def initialize(predictor)
    @predictor = predictor
  end

  def call(inputs)
    raise ArgumentError, "at most #{MAX_BATCH_SIZE} inputs" if inputs.length > MAX_BATCH_SIZE

    Async do
      barrier = Async::Barrier.new
      tasks = inputs.map do |input|
        barrier.async do
          begin
            prediction = @predictor.call(text: input)
            ConcurrentPredictionResult.new(input:, prediction:, error: nil)
          rescue StandardError => error
            ConcurrentPredictionResult.new(input:, prediction: nil, error:)
          end
        end
      end

      barrier.wait
      tasks.map(&:wait)
    end.wait
  end
end

predictor = DSPy::Predict.new(ClassifyText)
batch = ConcurrentPredictionBatch.new(predictor)
inputs = ["Excellent", "Needs work", "Ship it"]
results = batch.call(inputs)

results.each do |item|
  if item.error
    warn "#{item.input}: #{item.error.class}: #{item.error.message}"
  else
    puts "#{item.input}: #{item.prediction.sentiment}"
  end
end
```

The barrier joins every child task, and `tasks.map(&:wait)` preserves input order. Each child converts its own exception into a result, so one provider failure does not erase successful siblings. The batch rejects more than three inputs before creating tasks; use a worker pool or semaphore when the input source itself is unbounded. Timeouts, retries, idempotency, and cancellation remain application and provider concerns.

## Measure and Bound Concurrency

Concurrency overlaps waits only when the provider SDK and transport cooperate with Ruby's scheduler. Measure sequential and concurrent runs against the adapter, model, rate limit, and payload shape you deploy. Record wall-clock latency, successful throughput, provider throttles, timeouts, and partial failures.

The example's measured limit is `MAX_BATCH_SIZE`. Increase it only while throughput improves without unacceptable throttling, queue growth, or error rate; `Async::Barrier` joins tasks but does not rate-limit them.

## Continue

- Inspect concurrent spans in [Observability](/dspy.rb/production/observability/).
- Diagnose transport, timeout, and provider failures in [Troubleshooting](/dspy.rb/production/troubleshooting/).
