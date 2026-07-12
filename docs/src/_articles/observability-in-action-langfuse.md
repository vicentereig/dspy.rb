---
layout: blog
title: "Observability in Action: Langfuse Tracing"
description: "Configure DSPy.rb's optional Langfuse integration and inspect module, LM, and evaluation spans."
date: 2025-09-07
author: "Vicente Reig"
category: "Production"
reading_time: "8 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/observability-in-action-langfuse/"
image: /images/og/observability-in-action-langfuse.png
---

> You don't need Neo's Matrix X-Ray Vision to understand what's going on in your workflows and agents.

You do need traces. A typed result tells you whether the response fit the declared shape. It does not tell you which module ran, what the provider received, where time went, or why an agent selected a tool.

DSPy.rb instruments those boundaries with OpenTelemetry. The optional Langfuse gem exports the spans.

## Configure Langfuse

Add the observability gems:

```ruby
gem "dspy-o11y"
gem "dspy-o11y-langfuse"
```

Set the credentials expected by the integration:

```bash
export LANGFUSE_PUBLIC_KEY="pk-lf-..."
export LANGFUSE_SECRET_KEY="sk-lf-..."
export LANGFUSE_HOST="https://cloud.langfuse.com"
```

Loading DSPy.rb with those credentials present configures the integration. Applications that need explicit lifecycle control should also flush or shut down telemetry before a short-lived process exits.

## What the Trace Shows

![Langfuse raw telemetry stream showing continuous event flow](/dspy.rb/assets/images/langfuse-telemetry-stream.png)

DSPy modules create spans around `forward` calls and record serialized inputs, outputs, failures, and ancestry. LM calls add provider request timing, model metadata, and token usage when the provider reports it.

![Langfuse trace details showing hierarchical structure and reasoning](/dspy.rb/assets/images/langfuse-trace-details.png)

For a fixed workflow, the trace shows the sequence your Ruby code chose. For `ReAct` or `CodeAct`, it can also show iterations and tool or code-execution boundaries. The trace records execution; it does not prove the result was correct.

## Asynchronous Export

`DSPy::Observability::AsyncSpanProcessor` queues completed sampled spans and exports them on a dedicated single-thread executor. The request path enqueues the span rather than waiting for the Langfuse export.

The processor has bounded behavior:

- The default queue holds 1,000 spans.
- A full queue drops the oldest span and emits `observability.span_dropped`.
- It exports every 60 seconds or when 100 queued spans form a batch.
- Failed exports retry up to three times inside the exporter worker.
- `force_flush` and `shutdown` wait for queued work and return an OpenTelemetry export result.

Asynchronous export moves network work off the LM call path. It does not make export free, and a process that exits without flushing can lose queued spans.

## Scores Are Separate from Traces

Traces answer what ran. Scores attach an evaluation result to that execution. DSPy.rb's score-reporting support can send named values and comments to Langfuse when an application evaluates a prediction.

Keep the distinction visible:

- Runtime validation checks whether output matches the signature.
- A trace records how the program executed.
- A metric judges behavior against an example or criterion.
- Human review remains necessary where the metric cannot encode the decision.

## Operational Checks

Before relying on the integration:

1. Run one prediction and confirm its module and LM spans appear.
2. Verify that secrets and sensitive inputs are not recorded in attributes your application supplies.
3. Exercise `force_flush` in jobs or scripts that exit quickly.
4. Watch `observability.span_dropped` and export errors under load.
5. Treat missing token usage as provider metadata variance, not as zero usage.

The useful trace is the one that answers a production question. Everything else is storage with a dashboard.
