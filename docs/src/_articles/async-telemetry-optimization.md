---
layout: blog
title: "Making Telemetry Fast: Non-blocking Observability in DSPy.rb"
date: 2025-09-05
description: "How DSPy.rb's new async telemetry engine eliminates observability performance bottlenecks"
author: "Vicente Reig"
tags: ["performance", "observability", "async", "ruby"]
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/async-telemetry-optimization/"
---

# Making Telemetry Fast: Non-blocking Observability in DSPy.rb

If you've been using DSPy.rb with Langfuse tracing enabled, you might have noticed your tests running slower. That's because every time your code created a telemetry span, it had to wait for the HTTP export to Langfuse to complete. Not anymore.

## The Problem

OpenTelemetry's default `BatchSpanProcessor` exports spans in batches, which is good for throughput. But it still blocks your application thread during those HTTP calls to Langfuse. In a test suite with hundreds of spans, this adds up to significant slowdown.

## Our Solution: AsyncSpanProcessor

We built a custom span processor that makes telemetry truly non-blocking:

- **Immediate return**: Creating spans returns instantly, no waiting for HTTP calls
- **Background exports**: A separate background task handles all Langfuse communication  
- **Smart batching**: Exports happen every 5 seconds or when 100 spans accumulate
- **Overflow protection**: Drops oldest spans if the queue gets too full (1000 span limit)

The best part? It uses Ruby's `async` gem for proper fiber-based concurrency, so HTTP exports don't block anything else running in your application.

## Configuration

You can tune the behavior with environment variables:

```bash
# How many spans to queue before dropping old ones (default: 1000)
export DSPY_TELEMETRY_QUEUE_SIZE=2000

# How often to export in seconds (default: 5.0)
export DSPY_TELEMETRY_EXPORT_INTERVAL=10.0

# How many spans to export at once (default: 100)
export DSPY_TELEMETRY_BATCH_SIZE=50
```

But honestly, the defaults work great for most applications.

## Real Performance Numbers

We ran some benchmarks to see the difference:

**Before (blocking telemetry):**
- Creating 100 spans: ~200ms (lots of HTTP blocking)
- Test suite with Langfuse: Slow and painful

**After (async telemetry):**
- Creating 100 spans: ~19ms (almost instant)  
- Test suite improvement: 30-50% faster

Your LLM calls still work exactly the same, but now the telemetry doesn't slow them down.

## How It Works

The magic happens in a few key pieces:

1. **Thread::Queue**: Spans get queued instantly in a thread-safe way
2. **Background task**: A separate thread exports spans to Langfuse every few seconds
3. **Ruby's async gem**: HTTP exports use fiber-based concurrency, so they don't block
4. **Smart overflow**: If your app generates tons of spans, old ones get dropped to prevent memory issues

## Zero Migration Needed

The best part? You don't need to change any code. If you have Langfuse environment variables set (`LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY`), the async processor automatically takes over.

Your existing DSPy code keeps working exactly the same:

```ruby
DSPy::Context.with_span(operation: "my_operation") do
  # This now returns instantly instead of waiting for HTTP export
  my_llm_call()
end
```

## What This Means for You

- **Faster tests**: No more waiting for telemetry exports during test runs
- **Better production performance**: Your application threads don't get blocked by observability
- **Same great tracing**: All your Langfuse traces still work perfectly
- **Reliable under load**: Won't crash or slow down even with thousands of spans

The async telemetry engine makes DSPy.rb faster while keeping all the observability benefits you're used to. It just works better.