---
layout: docs
title: Score Reporting
name: Score Reporting
description: Create typed evaluation scores and export them to Langfuse with an explicit asynchronous lifecycle.
date: 2026-07-15 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
# Score Reporting

Attach a named evaluation result to an execution and, optionally, export it to Langfuse. A score reports metric output; it does not make a trace evidence of correctness.

## Prerequisites

Define the behavior being measured in [Evaluation](/dspy.rb/optimization/evaluation/) or [Custom Metrics](/dspy.rb/advanced/custom-metrics/). Langfuse is optional; install `dspy-o11y` and `dspy-o11y-langfuse`, then follow [Observability](/dspy.rb/production/observability/) only when scores must leave the process.

## Create and Export a Typed Score

The complete program creates one typed score, observes its `score.create` event, queues it for Langfuse, and shuts the exporter down. Save it as `report_score.rb` after installing the prerequisite packages.

<!-- score-reporting-program -->
```ruby
require 'dspy'
require 'dspy/o11y/langfuse'

exporter = DSPy::Observability::Adapters::Langfuse::ScoresExporter.configure(
  secret_key: ENV.fetch('LANGFUSE_SECRET_KEY'),
  public_key: ENV.fetch('LANGFUSE_PUBLIC_KEY'),
  host: ENV.fetch('LANGFUSE_HOST', 'https://cloud.langfuse.com')
)

observed_scores = []
subscription = DSPy.events.subscribe('score.create') do |_event_name, attributes|
  observed_scores << attributes
end

begin
  score = DSPy.score(
    'accuracy',
    0.95,
    comment: 'held-out evaluation',
    trace_id: 'evaluation-run-42'
  )
ensure
  DSPy.events.unsubscribe(subscription)
  exporter.shutdown
end

puts "#{score.name}=#{score.value} trace=#{score.trace_id}"
puts "events=#{observed_scores.length}"
```

`DSPy.score` returns a `DSPy::Scores::ScoreEvent` and emits `score.create`. `DataType::Numeric` is the default; pass `DataType::Boolean` for `0` or `1`, or `DataType::Categorical` for labels. Pass `trace_id:` or `observation_id:` when explicit correlation is required; otherwise the score uses current trace context when one exists.

The exporter consumes the same event asynchronously. Queueing is not delivery: network errors are retried up to `max_retries` and then logged. `shutdown` has a five-second default join timeout and may return without proving delivery or terminating the worker. Decide whether failed telemetry is best-effort or an operational alert.

## Use Built-in Evaluators

`DSPy::Scores::Evaluators` owns exact-match, containment, regex, length, similarity, and JSON-validity scoring. Each evaluator receives complete values and returns a `ScoreEvent`; for example, `exact_match(output: "Hello", expected: "hello", ignore_case: true)` returns a numeric score event.

Use [Custom Metrics](/dspy.rb/advanced/custom-metrics/) when those predicates do not represent the application outcome. To emit evaluation scores automatically, construct `DSPy::Evals` with an existing program and metric plus `export_scores: true` and `score_name: "qa_accuracy"`; the evaluator emits one score per example and a `qa_accuracy_batch` score. The default is `false`.

## Continue

- Build the underlying dataset and metric in [Evaluation](/dspy.rb/optimization/evaluation/).
- Define domain-specific scoring in [Custom Metrics](/dspy.rb/advanced/custom-metrics/).
- Correlate scores with execution in [Observability](/dspy.rb/production/observability/).
