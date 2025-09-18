---
layout: blog
title: "Concurrent LLM Processing: Real Performance Gains with Ruby's Async Ecosystem"
description: "See how DSPy.rb achieves 3x performance improvements using Ruby's excellent async capabilities. Real measurements from a practical coffee shop agent example."
date: 2024-09-07
author: "Vicente Reig"
category: "Performance"
reading_time: "7 min read"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/concurrent-llm-processing-performance-gains/"
image: /images/og/concurrent-llm-processing-performance-gains.png
---

Serving multiple customers efficiently isn't just a coffee shop problem—it's the core challenge of any LLM application at scale. When your AI agent needs to handle multiple requests, the difference between sequential and concurrent processing can make or break the user experience.

Today, we'll look at real performance gains using DSPy.rb's concurrent processing capabilities, built on Ruby's excellent [async ecosystem](https://github.com/socketry/async).

## The Problem: Sequential Bottlenecks

Let's start with a practical example. You've built an AI coffee shop agent that handles customer requests—making drinks, processing refunds, telling jokes, or escalating issues. Here's what sequential processing looks like:

```ruby
# Sequential processing - each customer waits for the previous one
agent.handle_customer(request: "Large iced latte with oat milk", mood: CustomerMood::Happy)     # 5.4s
agent.handle_customer(request: "This coffee is terrible!", mood: CustomerMood::Upset)           # 7.5s  
agent.handle_customer(request: "Do you sell hamburgers?", mood: CustomerMood::Neutral)          # 6.0s
agent.handle_customer(request: "Got any coffee jokes?", mood: CustomerMood::Happy)              # 6.1s
# Total time: ~25 seconds
```

The fourth customer waits 19 seconds before their request even starts processing. That's not acceptable for any real application.

## The Solution: Concurrent Processing

Ruby's [async gem](https://github.com/socketry/async) provides fiber-based concurrency that's perfect for I/O-bound operations like LLM API calls. Here's how DSPy.rb leverages it:

```ruby
Async do
  agent = CoffeeShopAgent.new
  barrier = Async::Barrier.new
  
  # All customer requests launch simultaneously
  barrier.async { agent.handle_customer(request: "Large iced latte...", mood: CustomerMood::Happy) }
  barrier.async { agent.handle_customer(request: "This coffee is terrible!", mood: CustomerMood::Upset) }
  barrier.async { agent.handle_customer(request: "Do you sell hamburgers?", mood: CustomerMood::Neutral) }
  barrier.async { agent.handle_customer(request: "Got any coffee jokes?", mood: CustomerMood::Happy) }
  
  # Wait for all to complete
  barrier.wait
end
# Total time: 7.53 seconds (limited by slowest request)
```

## Real Performance Results

Running both versions with identical customer requests, here are the measured results:

- **Sequential version**: ~25 seconds total
- **Concurrent version**: **7.53 seconds total**
- **Performance improvement**: **3.3x faster**

The improvement comes from processing all requests in parallel rather than waiting for each to complete sequentially.

You can see both implementations in the DSPy.rb repository:
- Sequential version
- Concurrent version

## How It Works: The Architecture

Here's how the concurrent processing flows through DSPy.rb's async architecture:

![Concurrent processing architecture diagram showing async task flow](/dspy.rb/assets/images/concurrent-architecture-diagram.svg)

### Key Components

1. **Async::Barrier**: Coordinates multiple concurrent tasks and waits for all to complete
2. **Customer Tasks**: Each request runs in its own fiber with isolated context  
3. **LM Chat Tasks**: The actual LLM API calls happen concurrently
4. **Background Telemetry**: Observability data is processed asynchronously without blocking

## Ruby's Async Ecosystem Excellence

Ruby's async processing capabilities have matured significantly. The [async gem](https://github.com/socketry/async) provides:

- **Fiber-based concurrency**: Lightweight, cooperative multitasking
- **Structured concurrency**: Clean task lifecycle management with automatic cleanup
- **Non-blocking I/O**: Perfect for API calls and database operations  
- **Zero thread overhead**: Fibers are much more efficient than threads for I/O-bound work

DSPy.rb builds on this solid foundation, providing async-aware features throughout the framework:

- [Concurrent predictions](https://vicentereig.github.io/dspy.rb/core-concepts/predictors/#concurrent-predictions) using `Async::Barrier`
- Fiber-local context management for clean request isolation
- Background telemetry processing with automatic retry handling
- Non-blocking observability that doesn't slow down your application

## Implementing Concurrent Processing

DSPy.rb makes concurrent processing straightforward. Here's the minimal code needed:

```ruby
require 'async'
require 'async/barrier'

# Your existing DSPy module
predictor = DSPy::ChainOfThought.new(YourSignature)

# Concurrent execution
Async do
  barrier = Async::Barrier.new
  
  requests.each do |request|
    barrier.async do
      result = predictor.call(**request)
      # Process result
    end
  end
  
  barrier.wait  # Wait for all to complete
end
```

Each prediction runs in its own fiber with isolated context. DSPy.rb's fiber-local storage ensures that temporary configuration changes (like switching models) don't interfere with concurrent requests.

## When Concurrent Processing Helps

Concurrent processing provides the biggest benefits when:

1. **I/O bound operations**: LLM API calls, database queries, external service calls
2. **Independent requests**: Tasks that don't depend on each other's results
3. **Variable response times**: Some requests are fast, others are slow
4. **Multiple data sources**: Calling different LLM providers or APIs simultaneously

For the coffee shop example, concurrent processing helps because:
- Each customer request is independent
- LLM API calls have variable response times (5-7 seconds)
- The agent makes external API calls that can be parallelized

## Measuring Your Own Performance

To measure concurrent processing benefits in your application:

```ruby
require 'benchmark'

# Benchmark sequential processing
sequential_time = Benchmark.measure do
  requests.each { |req| process_request(req) }
end

# Benchmark concurrent processing  
concurrent_time = Benchmark.measure do
  Async do
    barrier = Async::Barrier.new
    requests.each { |req| barrier.async { process_request(req) } }
    barrier.wait
  end
end

improvement = sequential_time.real / concurrent_time.real
puts "#{improvement.round(1)}x faster with concurrent processing"
```

## Beyond the Coffee Shop

The principles demonstrated here apply to any LLM application:

- **Content generation**: Process multiple articles simultaneously
- **Data analysis**: Analyze multiple datasets in parallel
- **Multi-step workflows**: Execute independent steps concurrently
- **Batch processing**: Handle multiple user requests efficiently

The key is identifying I/O-bound, independent operations that can benefit from concurrent execution.

## Practical Takeaways

1. **Ruby's async ecosystem is production-ready** - The async gem provides excellent concurrent processing capabilities
2. **Measure before optimizing** - Use real benchmarks to validate performance improvements
3. **Concurrent != complex** - DSPy.rb's `Async::Barrier` makes concurrent processing straightforward
4. **Context isolation matters** - Fiber-local storage prevents concurrent requests from interfering with each other
5. **Start small** - Begin with simple concurrent patterns and build complexity gradually

Ruby's async capabilities, combined with DSPy.rb's async-aware architecture, provide a solid foundation for building scalable LLM applications. The 3x performance improvement we demonstrated is achievable with minimal code changes.

The coffee shop agent example shows that concurrent processing benefits are real, measurable, and accessible—no theoretical performance claims, just practical improvements you can implement today.

---

*Try the concurrent coffee shop example yourself: clone the DSPy.rb repository and run both versions to see the performance difference firsthand.*