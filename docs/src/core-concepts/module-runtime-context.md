---
layout: docs
name: Module Runtime Context
description: Manage runtime behavior for DSPy.rb modules with fiber-local models, callbacks, and cross-cutting concerns.
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Module Runtime Context
  url: "/core-concepts/module-runtime-context/"
nav:
  prev:
    name: Modules
    url: "/core-concepts/modules/"
  next:
    name: Event System
    url: "/core-concepts/events/"
date: 2025-10-07 00:00:00 +0000
last_modified_at: 2025-10-07 00:00:00 +0000
---
# Module Runtime Context

Keep module behavior predictable in production by managing language model overrides, instrumentation hooks, and cross-cutting runtime concerns.

## Fiber-Local LM Context

DSPy.rb supports temporary language model overrides using fiber-local storage through `DSPy.with_lm`. This is particularly useful for optimization workflows, testing different models, or using specialized models for specific tasks.

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

# Powerful model for final results
powerful_model = DSPy::LM.new("anthropic/claude-3-opus-20240229", api_key: ENV['ANTHROPIC_API_KEY'])

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

# Use powerful model for production
DSPy.with_lm(powerful_model) do
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

## Lifecycle Callbacks

DSPy.rb modules support Rails-style lifecycle callbacks that run before, after, or around the `forward` method. This enables clean separation of concerns for cross-cutting concerns like logging, metrics, context management, and memory operations.

### Available Callback Types

- **`before`** - Runs before `forward` executes
- **`after`** - Runs after `forward` completes
- **`around`** - Wraps `forward` execution (must call `yield`)

### Basic Usage

#### Before Callbacks

Before callbacks execute before the `forward` method runs. They're useful for setup, initialization, or preparing context.

```ruby
class LoggingSignature < DSPy::Signature
  description "Answer questions with logging"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

class LoggingModule < DSPy::Module
  before :setup_context

  def initialize
    super
    @predictor = DSPy::Predict.new(LoggingSignature)
    @start_time = nil
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def setup_context
    @start_time = Time.now
    puts "Starting prediction at #{@start_time}"
  end
end

# Usage
module_instance = LoggingModule.new
result = module_instance.call(question: "What is DSPy.rb?")
# Output: "Starting prediction at 2025-10-06 12:00:00 -0700"
```

#### After Callbacks

After callbacks execute after the `forward` method completes. They're ideal for cleanup, logging results, or recording metrics.

```ruby
class MetricsModule < DSPy::Module
  after :log_metrics

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
    @start_time = nil
  end

  def forward(question:)
    @start_time = Time.now
    @predictor.call(question: question)
  end

  private

  def log_metrics
    duration = Time.now - @start_time
    puts "Prediction completed in #{duration} seconds"
  end
end

# Usage
module_instance = MetricsModule.new
result = module_instance.call(question: "Explain callbacks")
# Output: "Prediction completed in 1.23 seconds"
```

#### Around Callbacks

Around callbacks wrap the entire `forward` method execution. They must call `yield` to execute the wrapped method, and can perform actions both before and after.

```ruby
class MemoryModule < DSPy::Module
  around :manage_memory

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def manage_memory
    # Load context from memory
    context = load_context_from_memory
    puts "Loaded context: #{context}"

    # Execute the forward method
    result = yield

    # Save updated context
    save_context_to_memory(result)
    puts "Saved context to memory"

    result
  end

  def load_context_from_memory
    # Implementation
    {}
  end

  def save_context_to_memory(result)
    # Implementation
  end
end
```

### Combined Callbacks

You can use multiple callback types together. They execute in a specific order:

1. `before` callbacks
2. `around` callbacks (before `yield`)
3. `forward` method
4. `around` callbacks (after `yield`)
5. `after` callbacks

```ruby
class FullyInstrumentedModule < DSPy::Module
  before :setup_metrics
  after :log_metrics
  around :manage_context

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
    @metrics = {}
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def setup_metrics
    @metrics[:start_time] = Time.now
    puts "1. Before callback: Setting up metrics"
  end

  def manage_context
    puts "2. Around callback (before): Loading context"
    load_context

    result = yield

    puts "4. Around callback (after): Saving context"
    save_context

    result
  end

  def log_metrics
    @metrics[:duration] = Time.now - @metrics[:start_time]
    puts "5. After callback: Logged duration of #{@metrics[:duration]}s"
  end

  def load_context
    # Load from memory, database, etc.
  end

  def save_context
    # Save to memory, database, etc.
  end
end

# Usage
module_instance = FullyInstrumentedModule.new
result = module_instance.call(question: "What happens?")
# Output:
# 1. Before callback: Setting up metrics
# 2. Around callback (before): Loading context
# [forward method executes - step 3]
# 4. Around callback (after): Saving context
# 5. After callback: Logged duration of 1.23s
```

### Multiple Callbacks of Same Type

You can register multiple callbacks of the same type. They execute in registration order:

```ruby
class MultiCallbackModule < DSPy::Module
  before :first_setup
  before :second_setup
  before :third_setup

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def first_setup
    puts "First setup"
  end

  def second_setup
    puts "Second setup"
  end

  def third_setup
    puts "Third setup"
  end
end

# Callbacks execute in order: first_setup, second_setup, third_setup
```

### Inheritance

Callbacks are inherited from parent classes. Parent callbacks execute before child callbacks:

```ruby
class BaseModule < DSPy::Module
  before :base_setup

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def base_setup
    puts "Base setup"
  end
end

class DerivedModule < BaseModule
  before :derived_setup

  private

  def derived_setup
    puts "Derived setup"
  end
end
```

### Common Use Cases

Callbacks shine when you need to wire shared runtime responsibilities into multiple modules.

#### 1. Observability and Metrics

```ruby
class TelemetryModule < DSPy::Module
  around :measure_latency
  after :record_tokens

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def measure_latency
    start = Time.now
    result = yield

    duration = Time.now - start
    puts "Latency: #{duration}s"

    result
  end

  def record_tokens
    tokens_used = @predictor.last_response.tokens
    puts "Tokens used: #{tokens_used}"
  end
end
```

#### 2. Memory and State Management

```ruby
class StatefulModule < DSPy::Module
  around :manage_state

  def initialize(user_id:)
    super()
    @user_id = user_id
    @predictor = DSPy::ReAct.new(
      AssistantSignature,
      tools: DSPy::Tools::MemoryToolset.to_tools
    )
  end

  def forward(message:)
    @predictor.call(message: message, user_id: @user_id)
  end

  private

  def manage_state
    # Load user's conversation history
    load_conversation_history(@user_id)

    # Execute prediction
    result = yield

    # Save updated conversation
    save_conversation(@user_id, result)

    result
  end
end
```

#### 3. Rate Limiting and Circuit Breaking

```ruby
class RateLimitedModule < DSPy::Module
  before :check_rate_limit
  after :record_request

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
    @request_count = 0
    @last_reset = Time.now
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def check_rate_limit
    # Reset counter every minute
    if Time.now - @last_reset > 60
      @request_count = 0
      @last_reset = Time.now
    end

    raise "Rate limit exceeded" if @request_count >= 100
  end

  def record_request
    @request_count += 1
  end
end
```

#### 4. Error Recovery and Retry Logic

```ruby
class ResilientModule < DSPy::Module
  around :with_retry

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def with_retry
    max_retries = 3
    retry_count = 0

    begin
      yield
    rescue StandardError => e
      retry_count += 1
      if retry_count < max_retries
        sleep(2 ** retry_count) # Exponential backoff
        retry
      else
        raise e
      end
    end
  end
end
```

## Next Steps

- Explore [Production Observability](/production/observability/) for full telemetry pipelines.
- Combine callbacks with [Stateful Agents](/advanced/stateful-agents/) to scale conversational memory.
- Use the optimization guides under `/optimization/` once your modules expose the required instruction update contracts.
