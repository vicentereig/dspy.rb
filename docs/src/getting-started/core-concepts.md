---
layout: docs
published: false
name: Core Concepts
description: Learn how signatures, predictors, modules, examples, and agents fit together in DSPy.rb
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-08 00:00:00 +0000
---
# Core Concepts

DSPy.rb uses signatures to declare tasks and modules to execute them. Ruby composes modules into programs; `ReAct` adds a tool-selection loop when the model should choose the next action.

## Signatures: Defining LLM Interfaces

Signatures declare typed inputs, outputs, and task descriptions for model calls.

```ruby
class ClassifyText < DSPy::Signature
  description "Classify the sentiment and topic of the given text."

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :text, String
  end

  output do
    const :sentiment, Sentiment
    const :topic, String
    const :confidence, Float
  end
end
```

### What the Signature Provides

- **Runtime validation**: Sorbet types define the accepted result shape
- **Structured outputs**: Enums, objects, and arrays become output schemas
- **Task guidance**: Descriptions tell the model what each field means
- **Reuse**: One signature can serve several predictors and modules

## Predictors: Basic LLM Operations

Predictors execute signatures with a language model.

### DSPy::Predict

`Predict` makes one typed call and returns a structured result:

```ruby
classifier = DSPy::Predict.new(ClassifyText)
result = classifier.call(text: "I love this new restaurant!")

puts result.sentiment  # => #<Sentiment::Positive>
puts result.topic      # => "restaurant"
puts result.confidence # => 0.92
```

### DSPy::ChainOfThought

`ChainOfThought` adds a `reasoning` field before the signature outputs:

```ruby
class SolveMath < DSPy::Signature
  description "Solve the given math problem step by step."
  
  input { const :problem, String }
  output { const :solution, String }
end

solver = DSPy::ChainOfThought.new(SolveMath)
result = solver.call(problem: "If John has 15 apples and gives away 7, then buys 12 more, how many does he have?")

puts result.reasoning  # => "First, John starts with 15 apples..."
puts result.solution   # => "20 apples"
```

### DSPy::ReAct

`ReAct` runs a bounded loop in which the model can select typed tools:

```ruby
class Calculator < DSPy::Tools::Base
  tool_name "calculator"
  tool_description "Perform mathematical calculations"

  sig { params(operation: String, a: Float, b: Float).returns(T.any(Float, String)) }
  def call(operation:, a:, b:)
    case operation.downcase
    when "add"
      a + b
    when "multiply"
      a * b
    when "subtract"
      a - b
    when "divide"
      return "Error: Cannot divide by zero" if b == 0
      a / b
    else
      "Unknown operation: #{operation}"
    end
  end
end

class MathAgent < DSPy::Signature
  description "Solve math problems using available tools."

  input { const :problem, String }
  output { const :answer, T.any(Float, String) }
end

agent = DSPy::ReAct.new(MathAgent, tools: [Calculator.new])
result = agent.call(problem: "What is (15 + 7) * 3?")

# The agent will reason about the problem and use tools
puts result.answer # => 66.0 or "66"
```

## Modules: Composing Ruby Programs

Modules compose predictors with Ruby control flow.

```ruby
class DocumentProcessor < DSPy::Module
  def initialize
    @classifier = DSPy::Predict.new(ClassifyText)
    @summarizer = DSPy::Predict.new(SummarizeText)
  end
  
  def call(document)
    classification = @classifier.call(text: document)
    summary = @summarizer.call(text: document)
    
    {
      classification: classification,
      summary: summary,
      processed_at: Time.now
    }
  end
end
```

## Examples: Type-Safe Training Data

Examples provide type-safe training data for optimization:

```ruby
examples = [
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "This movie was amazing!" },
    expected: { sentiment: ClassifyText::Sentiment::Positive, confidence: 0.9 }
  ),
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "Terrible service, would not recommend." },
    expected: { sentiment: ClassifyText::Sentiment::Negative, confidence: 0.95 }
  )
]

# Define metric
exact_match = ->(example, prediction) {
  example.expected_values[:sentiment] == prediction.sentiment &&
  example.expected_values[:confidence] == prediction.confidence
}

# Evaluate a program against the examples
classifier = DSPy::Predict.new(ClassifyText)
evaluator = DSPy::Evals.new(classifier, metric: exact_match)
results = evaluator.evaluate(examples)
```

## Configuration: Setting Up Your Environment

Configure DSPy with a language model:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  
  # Optional: Configure logging for observability
  config.logger = Dry.Logger(:dspy)
end
```

### Language Model Options

DSPy.rb supports multiple LLM providers:

```ruby
# OpenAI
config.lm = DSPy::LM.new('openai/gpt-4o', api_key: ENV['OPENAI_API_KEY'])

# Anthropic
config.lm = DSPy::LM.new('anthropic/claude-sonnet-4-20250514', api_key: ENV['ANTHROPIC_API_KEY'])

# Per-module language model configuration
predictor = DSPy::Predict.new(ClassifyText)
predictor.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o')  # Override global LM for this instance
end
```

### Raw Chat API

Use `raw_chat` to benchmark an existing prompt or call a provider without DSPy's structured output features:

```ruby
lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

# Array format
response = lm.raw_chat([
  { role: 'system', content: 'You are a helpful assistant.' },
  { role: 'user', content: 'What is the capital of France?' }
])

# DSL format
response = lm.raw_chat do |m|
  m.system "You are a helpful assistant."
  m.user "What is the capital of France?"
  m.assistant "The capital of France is Paris."
  m.user "What about Spain?"
end
```

Use it for:
- Benchmarking monolithic prompts against modular implementations
- Gradual migration from existing prompt systems
- Quick prototyping without signatures

See the [benchmarking guide](/dspy.rb/optimization/benchmarking-raw-prompts/) for detailed examples.

## Error Handling and Validation

DSPy.rb raises typed configuration, validation, and provider errors:

```ruby
begin
  result = classifier.call(text: "Sample text")
rescue DSPy::PredictionInvalidError => e
  puts "Validation failed: #{e.message}"
  puts "Errors: #{e.errors}"
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
end
```

## Best Practices

### 1. Start Simple
Add reasoning or tools only when the task requires them:

```ruby
# Start with this
basic_classifier = DSPy::Predict.new(ClassifyText)

# Add reasoning when needed
reasoning_classifier = DSPy::ChainOfThought.new(ClassifyText)

# Add tools for complex tasks
agent_classifier = DSPy::ReAct.new(ComplexClassification, tools: [WebSearch.new])
```

### 2. Use Clear Descriptions
Descriptions become provider-facing task guidance. Measure their effect against examples and a metric:

```ruby
# Good: Clear and specific
description "Classify the sentiment of customer feedback as positive, negative, or neutral. Consider context and nuance."

# Bad: Vague
description "Classify text"
```

### 3. Leverage Type Safety
Use Sorbet types to reject results outside the declared shape:

```ruby
class Priority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
    Critical = new('critical')
  end
end

output do
  const :priority, Priority  # Type-safe enum
  const :confidence, Float   # Runtime validation
  const :metadata, T::Hash[String, String]  # Structured data
end
```

### 4. Keep Control Flow Explicit
Compose fixed steps as reusable Ruby modules. Use an agent only when the model has a useful action to choose:

```ruby
class EmailProcessor < DSPy::Module
  def initialize
    @classifier = DSPy::Predict.new(ClassifyEmail)
    @responder = DSPy::ChainOfThought.new(DraftResponse)
    @validator = DSPy::Predict.new(ValidateResponse)
  end
  
  def call(email)
    classification = @classifier.call(email: email)
    
    return early_response(classification) if simple_case?(classification)
    
    draft = @responder.call(email: email, context: classification)
    validation = @validator.call(response: draft.response)
    
    finalize_response(draft, validation)
  end
end
```

## Next Steps

- **[Signatures & Types](../../core-concepts/signatures)** - Design typed task contracts
- **[Predictors](../../core-concepts/predictors)** - Choose a predictor type
- **[Modules & Pipelines](../../core-concepts/modules)** - Compose modules with Ruby
- **[Examples & Validation](../../core-concepts/examples)** - Create evaluation and few-shot data

## Common Patterns

### Multi-Step Processing
```ruby
class DocumentAnalyzer < DSPy::Module
  def call(document)
    summary = @summarizer.call(text: document)
    topics = @topic_extractor.call(text: summary.summary)
    sentiment = @sentiment_analyzer.call(text: document)
    
    combine_results(summary, topics, sentiment)
  end
end
```

### Conditional Routing
```ruby
class SmartClassifier < DSPy::Module
  def call(text)
    complexity = @complexity_analyzer.call(text: text)
    
    if complexity.level == 'high'
      @reasoning_classifier.call(text: text)
    else
      @simple_classifier.call(text: text)
    end
  end
end
```

### Error Recovery
```ruby
class RobustProcessor < DSPy::Module
  def call(input)
    @primary_processor.call(input)
  rescue StandardError
    @fallback_processor.call(input)
  end
end
```

Signatures define tasks, modules execute them, and Ruby owns the program's control flow. Evaluation measures the complete program; optimizers can search its supported instructions and demonstrations.
