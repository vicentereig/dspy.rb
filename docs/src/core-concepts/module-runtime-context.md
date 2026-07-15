---
layout: docs
permalink: /advanced/module-runtime-context/
name: Module Runtime Context
description: Resolve and propagate language models through fiber-local and module runtime context.
date: 2025-10-07 00:00:00 +0000
last_modified_at: 2025-10-07 00:00:00 +0000
---
# Module Runtime Context

Module runtime context controls language-model resolution and propagation for a module call.

## Fiber-Local LM Context

`DSPy.with_lm` temporarily overrides the language model in fiber-local storage. Use it in optimization, model comparisons, or a Ruby program whose modules require different models.

### Basic Usage

```ruby
# Configure a global default model
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])
end

# Create a module that uses the global LM by default
class Classifier < DSPy::Module
  def initialize
    super
    @predictor = DSPy::Predict.new(ClassificationSignature)
  end

  def forward(text:)
    @predictor.call(text: text)
  end
end

classifier = Classifier.new

# Use the global LM (gpt-4o)
result1 = classifier.call(text: "This is great!")

# Temporarily override with a different model
fast_model = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

DSPy.with_lm(fast_model) do
  # Inside this block, all modules use the fast model
  result2 = classifier.call(text: "This is great!")
  # result2 was generated using gpt-4o-mini
end

# Back to using the global LM (gpt-4o)
result3 = classifier.call(text: "This is great!")
```

### LM Resolution Hierarchy

DSPy resolves language models in this order:
1. **Instance-level LM** - Set directly on a module instance
2. **Fiber-local LM** - Set via `DSPy.with_lm`
3. **Global LM** - Set via `DSPy.configure`

```ruby
# Global configuration
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])
end

# Create module with instance-level LM
classifier = Classifier.new
classifier.config.lm = DSPy::LM.new("anthropic/claude-sonnet-4-20250514", api_key: ENV['ANTHROPIC_API_KEY'])

# Instance-level LM takes precedence
result1 = classifier.call(text: "Test") # Uses Claude Sonnet

# Fiber-local LM doesn't override instance-level
fast_model = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
DSPy.with_lm(fast_model) do
  result2 = classifier.call(text: "Test") # Still uses Claude Sonnet
end

# Create module without instance-level LM
classifier2 = Classifier.new

DSPy.with_lm(fast_model) do
  result3 = classifier2.call(text: "Test") # Uses gpt-4o-mini (fiber-local)
end

result4 = classifier2.call(text: "Test") # Uses gpt-4o (global)
```

### Using with Different Model Types

```ruby
# Fast model for quick iterations
fast_model = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

# More capable model for final results
capable_model = DSPy::LM.new("anthropic/claude-3-opus-20240229", api_key: ENV['ANTHROPIC_API_KEY'])

# Local model for privacy-sensitive tasks
local_model = DSPy::LM.new("ollama/llama3.1:8b", base_url: "http://localhost:11434")

classifier = Classifier.new

# Use fast model for testing
DSPy.with_lm(fast_model) do
  test_results = test_cases.map do |test_case|
    classifier.call(text: test_case.text)
  end
  puts "Fast model accuracy: #{calculate_accuracy(test_results)}"
end

# Use the more capable model
DSPy.with_lm(capable_model) do
  production_result = classifier.call(text: user_input)
  send_response(production_result)
end

# Use local model for sensitive data
DSPy.with_lm(local_model) do
  sensitive_result = classifier.call(text: sensitive_document)
  store_locally(sensitive_result)
end
```

## Configuring Agent LMs

Complex agents like `ReAct` and `CodeAct` contain internal predictors. When you configure an agent's LM using `configure`, it automatically propagates to all child predictors.

### Basic Configuration

```ruby
# Configure a ReAct agent - LM propagates to internal predictors
agent = DSPy::ReAct.new(MySignature, tools: tools)
agent.configure { |c| c.lm = DSPy::LM.new('openai/gpt-4o', api_key: ENV['OPENAI_API_KEY']) }

# All internal predictors (thought_generator, observation_processor) now use gpt-4o
result = agent.call(question: "What is the capital of France?")
```

### Fine-Grained Control

Use `configure_predictor` to assign different LMs to specific internal predictors:

```ruby
# Use a fast model for most predictors
agent.configure { |c| c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }

# Use a more capable model for reasoning
agent.configure_predictor('thought_generator') do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o', api_key: ENV['OPENAI_API_KEY'])
end
```

Both methods support chaining:

```ruby
agent
  .configure { |c| c.lm = cheap_model }
  .configure_predictor('thought_generator') { |c| c.lm = expensive_model }
```

### Available Predictors by Agent Type

| Agent | Internal Predictors |
|-------|---------------------|
| `DSPy::ReAct` | `thought_generator`, `observation_processor` |
| `DSPy::CodeAct` | `code_generator`, `observation_processor` |
| `DSPy::DeepResearch` | `planner`, `synthesizer`, `qa_reviewer`, `reporter` |
| `DSPy::DeepSearch` | `seed_predictor`, `search_predictor`, `reader_predictor`, `reason_predictor` |

### Propagation Behavior

- **Recursive propagation**: Configuration propagates to children, grandchildren, etc.
- **Respects explicit configuration**: Children with already-configured LMs are not overwritten
- **Order matters**: Configure the parent first, then override specific children

```ruby
# This pattern works correctly:
agent.configure { |c| c.lm = default_lm }           # Sets on agent + all children
agent.configure_predictor('thought_generator') { |c| c.lm = special_lm }  # Overrides one child

# Children configured before parent retain their configuration:
thought_gen = agent.named_predictors.find { |n, _| n == 'thought_generator' }.last
thought_gen.configure { |c| c.lm = special_lm }     # Configure child first
agent.configure { |c| c.lm = default_lm }           # Parent config won't overwrite
```

<span id="lifecycle-callbacks" data-canonical-route="/advanced/module-lifecycle-callbacks/"></span>
<span id="available-callback-types"></span><span id="basic-usage-1"></span><span id="before-callbacks"></span><span id="after-callbacks"></span><span id="around-callbacks"></span><span id="combined-callbacks"></span><span id="multiple-callbacks-of-same-type"></span><span id="inheritance"></span><span id="common-use-cases"></span><span id="1-observability-and-metrics"></span><span id="2-memory-and-state-management"></span><span id="3-rate-limiting-and-circuit-breaking"></span><span id="4-error-recovery-and-retry-logic"></span>

## Add Module Lifecycle Callbacks

Callbacks are a separate module-authoring task. See [Module Lifecycle Callbacks](/dspy.rb/advanced/module-lifecycle-callbacks/) for the canonical `before`, `around`, and `after` definitions, order, inheritance, and failure boundary.

## Continue to Observability, State, or Optimization {#next-steps}

- Add [Production Observability](/dspy.rb/production/observability/) when module events need a telemetry pipeline.
- Combine callbacks with [Stateful Agents](/dspy.rb/advanced/stateful-agents/) when the application owns conversational memory.
- Use the optimization guides under `/optimization/` once your modules expose the required instruction update contracts.
