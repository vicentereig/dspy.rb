---
layout: blog
order: 9
title: "Raw Chat API for Benchmarking and Migration"
date: 2025-07-23
description: "Learn how to use DSPy.rb's raw_chat API for benchmarking monolithic prompts and migrating to modular implementations"
tags: [api, benchmarking, migration, instrumentation]
excerpt: |
  The new raw_chat API enables running legacy prompts through DSPy's instrumentation pipeline, making it easy to benchmark and migrate from monolithic to modular prompt architectures.
permalink: /blog/raw-chat-api/
---

# Raw Chat API for Benchmarking and Migration

DSPy.rb 0.x.x introduces the `raw_chat` API, a powerful feature designed to help teams benchmark their existing monolithic prompts and facilitate gradual migration to DSPy's modular approach.

## The Challenge

Many teams have existing systems built around large, monolithic prompts. While DSPy's modular approach offers significant benefits—type safety, composability, and automatic optimization—it's not always clear whether migrating will improve performance or reduce costs.

The `raw_chat` API solves this by allowing you to:
- Run existing prompts through DSPy's instrumentation pipeline
- Compare token usage between monolithic and modular approaches
- Measure performance across different providers
- Make data-driven migration decisions

## API Overview

The `raw_chat` method provides a direct interface to language models without DSPy's structured output features:

```ruby
# Initialize a language model
lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

# Array format
response = lm.raw_chat([
  { role: 'system', content: 'You are a helpful assistant.' },
  { role: 'user', content: 'What is the capital of France?' }
])

# DSL format for cleaner syntax
response = lm.raw_chat do |m|
  m.system "You are a helpful assistant."
  m.user "What is the capital of France?"
end
```

## Key Features

### 1. Full Instrumentation Support

Unlike bypassing DSPy entirely, `raw_chat` emits all standard instrumentation events:

```ruby
# These events are emitted for raw_chat:
# - dspy.lm.request (with signature_class: 'RawPrompt')
# - dspy.lm.tokens (with accurate token counts)
# 
# NOT emitted:
# - dspy.lm.response.parsed (since there's no JSON parsing)
```

### 2. Message Builder DSL

The DSL provides a clean way to construct conversations:

```ruby
lm.raw_chat do |m|
  m.user "My name is Alice"
  m.assistant "Nice to meet you, Alice!"
  m.user "What's my name?"
end
```

### 3. Streaming Support

Stream responses for real-time applications:

```ruby
lm.raw_chat(messages) do |chunk|
  print chunk
end
```

## Real-World Example: Changelog Generation

Here's how a team might compare their existing changelog generator with a DSPy implementation:

```ruby
# Legacy monolithic prompt
LEGACY_PROMPT = <<~PROMPT
  You are an expert changelog generator. Given git commits:
  1. Parse each commit type and description
  2. Group by type (feat, fix, chore, etc.)
  3. Generate user-friendly descriptions
  4. Format as markdown
  5. Highlight breaking changes
  Be concise but informative.
PROMPT

# Capture instrumentation data
events = []
DSPy::Instrumentation.subscribe { |e| events << e }

# Benchmark legacy approach
legacy_result = lm.raw_chat do |m|
  m.system LEGACY_PROMPT
  m.user commits.join("\n")
end

legacy_tokens = events.find { |e| e.id == 'dspy.lm.tokens' }.payload

# Clear events and benchmark modular approach
events.clear
generator = DSPy::ChainOfThought.new(ChangelogSignature)
modular_result = generator.forward(commits: commits)

modular_tokens = events.find { |e| e.id == 'dspy.lm.tokens' }.payload

# Compare results
puts "Legacy: #{legacy_tokens[:total_tokens]} tokens"
puts "Modular: #{modular_tokens[:total_tokens]} tokens"
puts "Reduction: #{((1 - modular_tokens[:total_tokens].to_f / legacy_tokens[:total_tokens]) * 100).round(2)}%"
```

## Integration with Observability

Since `raw_chat` uses the same instrumentation pipeline, it works seamlessly with all DSPy observability tools:

```ruby
# Configure DataDog
DSPy.configure do |config|
  config.instrumentation.subscribers = [
    DSPy::Subscribers::DatadogSubscriber.new
  ]
end

# Both calls are tracked identically
lm.raw_chat([{ role: 'user', content: 'Hello' }])
predictor.forward(input: 'Hello')
```

## Migration Strategy

The `raw_chat` API enables a phased migration approach:

### Phase 1: Baseline
```ruby
# Measure existing prompt performance
baseline = benchmark_with_raw_chat(LEGACY_PROMPT, test_dataset)
```

### Phase 2: Prototype
```ruby
# Build modular version
class ModularImplementation < DSPy::Module
  # ...
end
```

### Phase 3: Compare
```ruby
# Run side-by-side comparison
results = compare_approaches(baseline, ModularImplementation.new)
```

### Phase 4: Migrate
```ruby
# Deploy when metrics improve
if results[:modular][:tokens] < results[:legacy][:tokens] * 0.9
  deploy_modular_version
end
```

## Implementation Details

Under the hood, `raw_chat`:

1. **Bypasses JSON parsing** - Returns raw string responses
2. **Skips retry strategies** - No structured output validation
3. **Direct adapter calls** - Minimal overhead
4. **Preserves instrumentation** - Full observability

This design ensures fair comparisons while maintaining DSPy's monitoring capabilities.

## Best Practices

1. **Consistent test data** - Use identical inputs for fair comparison
2. **Multiple runs** - Average results to account for variance
3. **Quality metrics** - Don't optimize for tokens alone
4. **Gradual migration** - Start with non-critical prompts
5. **Monitor production** - Track real-world improvements

## Conclusion

The `raw_chat` API bridges the gap between legacy prompt systems and modern DSPy applications. By providing accurate benchmarking capabilities with full instrumentation support, it enables teams to make informed decisions about when and how to adopt DSPy's modular approach.

Whether you're evaluating DSPy for the first time or planning a large-scale migration, `raw_chat` provides the tools you need to measure, compare, and optimize your prompt architecture with confidence.

---

*Ready to benchmark your prompts? Check out the [complete benchmarking guide](/optimization/benchmarking-raw-prompts/) for detailed examples and best practices.*