---
layout: docs
title: "Benchmarking Raw Prompts"
description: "Compare monolithic prompts against modular DSPy implementations"
order: 6
---

# Benchmarking Raw Prompts

When migrating from monolithic prompts to modular DSPy implementations, it's crucial to measure and compare their performance. DSPy.rb provides the `raw_chat` method specifically for this purpose, allowing you to run existing prompts through the same instrumentation pipeline as your DSPy modules.

## Why Benchmark Raw Prompts?

1. **Fair Comparison**: Compare apples-to-apples between monolithic and modular approaches
2. **Migration Path**: Gradually migrate existing prompts while measuring impact
3. **Cost Analysis**: Accurate token usage comparison for budget planning
4. **Performance Metrics**: Measure latency, token efficiency, and quality

## Using raw_chat

The `raw_chat` method supports two formats: array format and DSL format.

### Array Format

```ruby
lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

# Run a raw prompt
result = lm.raw_chat([
  { role: 'system', content: 'You are a helpful assistant.' },
  { role: 'user', content: 'What is the capital of France?' }
])

puts result # => "The capital of France is Paris."
```

### DSL Format

```ruby
result = lm.raw_chat do |m|
  m.system "You are a changelog generator. Format output as markdown."
  m.user "Generate a changelog for: feat: Add user auth, fix: Memory leak"
end

puts result # => "# Changelog\n\n## Features\n- Add user authentication..."
```

## Capturing Instrumentation Data

Both `raw_chat` and regular DSPy modules emit the same instrumentation events, making comparison straightforward:

```ruby
# Capture events for analysis
captured_events = []
DSPy::Instrumentation.subscribe do |event|
  captured_events << event
end

# Run monolithic prompt
monolithic_result = lm.raw_chat do |m|
  m.system MONOLITHIC_CHANGELOG_PROMPT
  m.user commit_data
end

# Extract token usage
monolithic_tokens = captured_events
  .select { |e| e.id == 'dspy.lm.tokens' }
  .last
  .payload

# Clear events for next test
captured_events.clear

# Run modular DSPy version
changelog_generator = DSPy::ChainOfThought.new(ChangelogSignature)
modular_result = changelog_generator.forward(commits: commit_data)

# Extract token usage
modular_tokens = captured_events
  .select { |e| e.id == 'dspy.lm.tokens' }
  .last
  .payload

# Compare results
puts "Monolithic: #{monolithic_tokens[:total_tokens]} tokens"
puts "Modular: #{modular_tokens[:total_tokens]} tokens"
puts "Savings: #{((1 - modular_tokens[:total_tokens].to_f / monolithic_tokens[:total_tokens]) * 100).round(2)}%"
```

## Complete Benchmarking Example

Here's a complete example comparing a monolithic changelog generator with a modular DSPy implementation:

```ruby
require 'dspy'

# Monolithic prompt (from legacy system)
MONOLITHIC_PROMPT = <<~PROMPT
  You are an expert changelog generator. Given a list of git commits, you must:
  
  1. Parse each commit message to understand the change type and description
  2. Group commits by type (feat, fix, chore, docs, etc.)
  3. Generate clear, user-friendly descriptions for each change
  4. Format the output as a well-structured markdown changelog
  5. Highlight any breaking changes prominently
  6. Order sections by importance: Breaking Changes, Features, Fixes, Others
  
  Be concise but informative. Focus on what users need to know.
PROMPT

# Modular DSPy signature
class ChangelogSignature < DSPy::Signature
  input do
    const :commits, T::Array[String], description: "List of git commit messages"
  end
  
  output do
    const :changelog, String, description: "Formatted markdown changelog"
    const :breaking_changes, T::Array[String], description: "List of breaking changes"
  end
end

# Benchmark function
def benchmark_approaches(commits_data)
  lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  
  results = {}
  
  # Benchmark monolithic approach
  start_time = Time.now
  events = []
  
  DSPy::Instrumentation.subscribe { |e| events << e }
  
  monolithic_result = lm.raw_chat do |m|
    m.system MONOLITHIC_PROMPT
    m.user commits_data.join("\n")
  end
  
  monolithic_time = Time.now - start_time
  monolithic_tokens = events.find { |e| e.id == 'dspy.lm.tokens' }&.payload
  
  results[:monolithic] = {
    time: monolithic_time,
    tokens: monolithic_tokens,
    result: monolithic_result
  }
  
  # Reset
  events.clear
  
  # Benchmark modular approach
  start_time = Time.now
  
  generator = DSPy::ChainOfThought.new(ChangelogSignature)
  modular_result = generator.forward(commits: commits_data)
  
  modular_time = Time.now - start_time
  modular_tokens = events.find { |e| e.id == 'dspy.lm.tokens' }&.payload
  
  results[:modular] = {
    time: modular_time,
    tokens: modular_tokens,
    result: modular_result.changelog
  }
  
  results
end

# Run benchmark
commits = [
  "feat: Add user authentication system",
  "fix: Resolve memory leak in worker process",
  "feat!: Change API response format",
  "docs: Update installation guide",
  "chore: Upgrade dependencies"
]

results = benchmark_approaches(commits)

# Display results
puts "=== Benchmark Results ==="
puts "\nMonolithic Approach:"
puts "  Time: #{results[:monolithic][:time].round(3)}s"
puts "  Tokens: #{results[:monolithic][:tokens][:total_tokens]}"
puts "  Cost: $#{(results[:monolithic][:tokens][:total_tokens] * 0.00015 / 1000).round(4)}"

puts "\nModular Approach:"
puts "  Time: #{results[:modular][:time].round(3)}s"
puts "  Tokens: #{results[:modular][:tokens][:total_tokens]}"
puts "  Cost: $#{(results[:modular][:tokens][:total_tokens] * 0.00015 / 1000).round(4)}"

# Calculate improvements
token_reduction = ((1 - results[:modular][:tokens][:total_tokens].to_f / 
                       results[:monolithic][:tokens][:total_tokens]) * 100).round(2)

puts "\nImprovements:"
puts "  Token reduction: #{token_reduction}%"
puts "  Additional benefits: Type safety, testability, composability"
```

## Advanced Benchmarking with Multiple Providers

Compare performance across different LLM providers:

```ruby
def benchmark_providers(prompt_messages)
  providers = [
    { id: 'openai/gpt-4o-mini', key: ENV['OPENAI_API_KEY'] },
    { id: 'anthropic/claude-3-5-sonnet-20241022', key: ENV['ANTHROPIC_API_KEY'] }
  ]
  
  results = {}
  
  providers.each do |provider|
    lm = DSPy::LM.new(provider[:id], api_key: provider[:key])
    
    events = []
    DSPy::Instrumentation.subscribe { |e| events << e }
    
    start_time = Time.now
    result = lm.raw_chat(prompt_messages)
    elapsed = Time.now - start_time
    
    token_event = events.find { |e| e.id == 'dspy.lm.tokens' }
    
    results[provider[:id]] = {
      response: result,
      time: elapsed,
      tokens: token_event&.payload
    }
  end
  
  results
end
```

## Integration with Observability Tools

The `raw_chat` method emits standard DSPy instrumentation events, making it compatible with all observability integrations:

```ruby
# Configure DataDog integration
DSPy.configure do |config|
  config.instrumentation.subscribers = [
    DSPy::Subscribers::DatadogSubscriber.new
  ]
end

# Both raw and modular prompts will be tracked
lm.raw_chat([{ role: 'user', content: 'Hello' }])  # Tracked in DataDog
predictor.forward(input: 'Hello')                   # Also tracked in DataDog
```

## Best Practices

1. **Use Consistent Test Data**: Ensure both approaches receive identical inputs
2. **Multiple Runs**: Average results across multiple runs to account for variance
3. **Consider Quality**: Token count isn't everything - evaluate output quality too
4. **Track Over Time**: Monitor performance as you migrate from monolithic to modular
5. **Use with CI/CD**: Integrate benchmarks into your deployment pipeline

## Migration Strategy

```ruby
# Phase 1: Benchmark existing prompts
baseline = benchmark_raw_prompt(LEGACY_PROMPT, test_data)

# Phase 2: Create modular version
class ModularVersion < DSPy::Module
  # Implementation
end

# Phase 3: Compare and validate
comparison = benchmark_modular(ModularVersion.new, test_data)

# Phase 4: Deploy if metrics improve
if comparison[:tokens] < baseline[:tokens] * 0.9  # 10% improvement
  deploy_modular_version
else
  optimize_further
end
```

## Conclusion

The `raw_chat` method provides a crucial bridge for teams migrating from monolithic prompts to modular DSPy implementations. By enabling direct performance comparisons with full instrumentation support, it helps make data-driven decisions about when and how to modularize your prompts.

Remember: while token efficiency is important, the real benefits of DSPy's modular approach include improved maintainability, testability, and the ability to optimize prompts programmatically.