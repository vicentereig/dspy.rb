---
layout: docs
title: Benchmarking Raw Prompts
description: Compare monolithic prompts against modular DSPy implementations
date: 2025-07-23 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
# Benchmarking Raw Prompts

Use `raw_chat` to establish a baseline for an existing provider prompt before replacing it with a typed module. Compare both implementations with the same model, inputs, metric, and telemetry.

## Establish a Comparable Baseline

1. **Comparable inputs**: Run both implementations with the same model and data.
2. **Measured migration**: Replace prompts incrementally while recording behavior changes.
3. **Cost evidence**: Compare token usage under the same workload.
4. **Operational evidence**: Record latency beside the task metric.

## Using raw_chat

The `raw_chat` method supports two formats: array format and DSL format.

### Array Format

```ruby
lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

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

## Capturing Observability Data

Both `raw_chat` and DSPy modules emit `lm.tokens` events. Subscribe around one call so each measurement owns its event buffer and elapsed time:

```ruby
def measure_call
  token_events = []
  subscription_id = DSPy.events.subscribe("lm.tokens") do |_name, attributes|
    token_events << attributes
  end

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  value = yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  total_tokens = token_events.sum do |attributes|
    attributes[:total_tokens] || attributes["total_tokens"] || 0
  end

  { value: value, seconds: elapsed, total_tokens: total_tokens }
ensure
  DSPy.events.unsubscribe(subscription_id) if subscription_id
end
```

## Run a Changelog Benchmark

The following example compares a monolithic changelog generator with a modular DSPy implementation:

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

  monolithic = measure_call do
    lm.raw_chat do |m|
      m.system MONOLITHIC_PROMPT
      m.user commits_data.join("\n")
    end
  end

  generator = DSPy::ChainOfThought.new(ChangelogSignature)
  generator.configure { |config| config.lm = lm }
  modular = measure_call do
    generator.call(commits: commits_data)
  end

  {
    monolithic: monolithic,
    modular: modular.merge(value: modular[:value].changelog)
  }
end

commits = [
  "feat: Add user authentication system",
  "fix: Resolve memory leak in worker process",
  "feat!: Change API response format",
  "docs: Update installation guide",
  "chore: Upgrade dependencies"
]

results = benchmark_approaches(commits)

puts "=== Benchmark Results ==="
puts "\nMonolithic Approach:"
puts "  Time: #{results[:monolithic][:seconds].round(3)}s"
puts "  Tokens: #{results[:monolithic][:total_tokens]}"

puts "\nModular Approach:"
puts "  Time: #{results[:modular][:seconds].round(3)}s"
puts "  Tokens: #{results[:modular][:total_tokens]}"

token_reduction = ((1 - results[:modular][:total_tokens].to_f /
                       results[:monolithic][:total_tokens]) * 100).round(2)

puts "\nImprovements:"
puts "  Token reduction: #{token_reduction}%"
puts "  Additional benefits: Type safety, testability, composability"
```

## Compare Multiple Providers

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
    results[provider[:id]] = measure_call { lm.raw_chat(prompt_messages) }
  end
  
  results
end
```

## Capture Both Paths in Observability

`raw_chat` emits DSPy log events and spans; configure the selected observability integration to capture both paths:

```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(stream: "/var/log/dspy/benchmarks.json")
  end
end

# Both raw and modular prompts will be logged
lm.raw_chat([{ role: 'user', content: 'Hello' }])  # Logged as llm.generate
predictor.forward(input: 'Hello')                   # Logged as dspy.predict
```

## Benchmarking Schema Formats

DSPy.rb supports JSON Schema and BAML schema rendering. Measure both formats on your actual signature; the difference depends on schema shape and provider formatting.

```ruby
json_lm = DSPy::LM.new(
  'openai/gpt-4o-mini',
  api_key: ENV['OPENAI_API_KEY'],
  schema_format: :json
)

baml_lm = DSPy::LM.new(
  'openai/gpt-4o-mini',
  api_key: ENV['OPENAI_API_KEY'],
  schema_format: :baml
)

# Benchmark a rich signature
class TaskDecomposition < DSPy::Signature
  description "Analyze topic and define optimal subtasks"

  input do
    const :topic, String
    const :context, String
  end

  output do
    const :subtasks, T::Array[String]
    const :task_types, T::Array[String]
    const :priority_order, T::Array[Integer]
    const :estimated_effort, T::Array[Integer]
    const :dependencies, T::Array[String]
  end
end

DSPy.configure { |c| c.lm = json_lm }
json_predictor = DSPy::Predict.new(TaskDecomposition)
json_result = json_predictor.call(
  topic: "Sustainable technology adoption",
  context: "Focus on practical challenges"
)

DSPy.configure { |c| c.lm = baml_lm }
baml_predictor = DSPy::Predict.new(TaskDecomposition)
baml_result = baml_predictor.call(
  topic: "Sustainable technology adoption",
  context: "Focus on practical challenges"
)

# Record input tokens and output quality for each run.
```

Do not infer output quality from schema length. Compare validation failures and task metrics beside token counts.

See [Schema Formats](/dspy.rb/core-concepts/signatures/#schema-formats) for detailed comparison.

## Keep the Benchmark Comparable

1. **Use Consistent Test Data**: Ensure both approaches receive identical inputs
2. **Multiple Runs**: Average results across multiple runs to account for variance
3. **Measure task behavior**: Record the chosen metric beside token counts
4. **Track Over Time**: Monitor performance as you migrate from monolithic to modular
5. **Use with CI/CD**: Integrate benchmarks into your deployment pipeline
6. **Test Schema Formats**: For rich signatures, benchmark BAML vs JSON Schema to measure token savings

## Migration Strategy

```ruby
baseline = benchmark_raw_prompt(LEGACY_PROMPT, test_data)

class ModularVersion < DSPy::Module
  # Implementation
end

comparison = benchmark_modular(ModularVersion.new, test_data)

if comparison[:tokens] < baseline[:tokens] * 0.9  # 10% improvement
  deploy_modular_version
else
  optimize_further
end
```

Keep the baseline when the module does not improve the metric or operational boundary that motivated the migration. A typed interface is useful, but it does not make a weaker result acceptable.
