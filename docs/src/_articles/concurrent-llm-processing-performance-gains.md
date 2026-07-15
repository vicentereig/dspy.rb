---
layout: blog
title: "Concurrent LLM Processing with Ruby's Async Ecosystem"
description: "Run independent DSPy.rb calls in sibling Async tasks, measure the result, and check whether the provider transport yields cooperatively."
date: 2024-09-07
author: "Vicente Reig"
category: "Performance"
reading_time: "7 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/concurrent-llm-processing-performance-gains/"
image: /images/og/concurrent-llm-processing-performance-gains.png
---

Four independent LLM requests do not need to wait for one another. Ruby's [async ecosystem](https://github.com/socketry/async) gives us a structured way to start them together and wait for the complete batch.

That can reduce wall-clock time when the provider client's network operations cooperate with Ruby's fiber scheduler. It does not make an individual request faster, and the gain depends on the workload, rate limits, connection pool, and provider transport.

## Start with the sequential program

The coffee shop example handles four unrelated requests:

```ruby
# Sequential processing - each customer waits for the previous one
agent.handle_customer(request: "Large iced latte with oat milk", mood: CustomerMood::Happy)
agent.handle_customer(request: "This coffee is terrible!", mood: CustomerMood::Upset)
agent.handle_customer(request: "Do you sell hamburgers?", mood: CustomerMood::Neutral)
agent.handle_customer(request: "Got any coffee jokes?", mood: CustomerMood::Happy)
```

The control flow is fixed: Ruby sends each request after the previous call returns. Nothing about the program requires that ordering.

## Run independent calls as sibling tasks

`Async::Barrier` owns the child tasks and waits for all of them:

```ruby
require 'async'
require 'async/barrier'

Async do
  agent = CoffeeShopAgent.new
  barrier = Async::Barrier.new

  barrier.async { agent.handle_customer(request: "Large iced latte...", mood: CustomerMood::Happy) }
  barrier.async { agent.handle_customer(request: "This coffee is terrible!", mood: CustomerMood::Upset) }
  barrier.async { agent.handle_customer(request: "Do you sell hamburgers?", mood: CustomerMood::Neutral) }
  barrier.async { agent.handle_customer(request: "Got any coffee jokes?", mood: CustomerMood::Happy) }

  barrier.wait
end
```

Each DSPy module call remains ordinary Ruby. `Async` supplies the reactor; the barrier supplies task ownership and a completion boundary. DSPy.rb does not create the four tasks for you.

The [Concurrent Predictions guide](https://oss.vicente.services/dspy.rb/advanced/concurrent-predictions/) shows the same application-owned concurrency boundary for DSPy modules.

The original coffee shop run reported about 25 seconds sequentially and 7.53 seconds concurrently, or roughly 3.3x. The repository no longer contains the runnable example or benchmark artifact needed to reproduce that result, so treat those numbers as a historical observation, not a current benchmark.

![Concurrent processing architecture diagram showing async task flow](/dspy.rb/assets/images/concurrent-architecture-diagram.svg)

## What must be true

Concurrency helps only when:

- The calls are independent.
- Waiting dominates the work.
- The provider client yields during network I/O.
- Connection and rate limits permit overlap.
- Shared state is safe to access from sibling tasks.

Ruby fibers use cooperative scheduling. A blocking provider SDK can stop the reactor even though the application created several tasks. Verify the transport you deploy instead of inferring behavior from the presence of `Async`.

Fiber-local model selection also has a narrower job. `DSPy.with_lm` keeps a temporary model override in the current fiber and restores it after the block. It prevents one task's model choice from changing another task's choice; it does not make the underlying client concurrent.

## Measure the deployed path

Measure the same requests through the same adapter, credentials, network, and limits you expect to use:

```ruby
require 'async'
require 'async/barrier'
require 'benchmark'

sequential_time = Benchmark.realtime do
  requests.each { |request| process_request(request) }
end

concurrent_time = Benchmark.realtime do
  Async do
    barrier = Async::Barrier.new
    requests.each do |request|
      barrier.async { process_request(request) }
    end
    barrier.wait
  end
end

puts "sequential: #{sequential_time.round(2)}s"
puts "concurrent: #{concurrent_time.round(2)}s"
puts "ratio: #{(sequential_time / concurrent_time).round(2)}x"
```

Run more than one sample, warm connection pools first, and record failures and rate-limit responses alongside elapsed time. A faster run that drops requests is not an improvement.

Use concurrency for independent calls. Keep dependent steps in ordinary Ruby control flow, and put an explicit limit around large batches rather than launching every request at once.
