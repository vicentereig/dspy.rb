---
layout: docs
name: Core Concepts
description: Understand the fundamental building blocks of DSPy.rb
breadcrumb:
- name: Getting Started
  url: "/getting-started/"
- name: Core Concepts
  url: "/getting-started/core-concepts/"
prev:
  name: Quick Start
  url: "/getting-started/quick-start/"
next:
  name: Signatures
  url: "/core-concepts/signatures/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-08 00:00:00 +0000
---
# Core Concepts

DSPy.rb is built around composable, type-safe modules that make LLM programming predictable and reliable. This guide covers the fundamental concepts you need to understand to build effective DSPy applications.

## Signatures: Defining LLM Interfaces

Signatures are the foundation of DSPy. They define typed interfaces for LLM operations, specifying inputs, outputs, and behavior descriptions.

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

### Key Features

- **Type Safety**: Signatures use Sorbet types to ensure runtime type checking
- **Structured Outputs**: Define complex output schemas with enums, objects, and arrays
- **Self-Documenting**: Descriptions provide context to the LLM about the task
- **Composable**: Signatures can be reused across different predictors and modules

## Predictors: Basic LLM Operations

Predictors are the basic building blocks that execute signatures using language models.

### DSPy::Predict

The simplest predictor that takes a signature and returns structured results:

```ruby
classifier = DSPy::Predict.new(ClassifyText)
result = classifier.call(text: "I love this new restaurant!")

puts result.sentiment  # => #<Sentiment::Positive>
puts result.topic      # => "restaurant"
puts result.confidence # => 0.92
```

### DSPy::ChainOfThought

Adds step-by-step reasoning to improve accuracy on complex tasks:

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

Combines reasoning with action - perfect for agents that need to use tools:

```ruby
class Calculator < DSPy::Tools::Base
  extend T::Sig
  
  tool_name "calculator"
  tool_description "Perform mathematical calculations"
  
  sig { params(operation: String, a: Float, b: Float).returns(String) }
  def call(operation:, a:, b:)
    case operation
    when "add"
      (a + b).to_s
    when "multiply"
      (a * b).to_s
    else
      "Unknown operation"
    end
  end
end

class MathAgent < DSPy::Signature
  description "Solve math problems using available tools."
  
  input { const :problem, String }
  output { const :answer, String }
end

agent = DSPy::ReAct.new(MathAgent, tools: [Calculator.new])
result = agent.call(problem: "What is (15 + 7) * 3?")

# The agent will reason about the problem and use tools
puts result.answer # => "66"
```

## Modules: Composing Complex Workflows

Modules let you compose multiple predictors into sophisticated pipelines.

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
      processed_at: Time.current
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

# Use examples for evaluation
evaluator = DSPy::Evaluate.new(metric: :exact_match)
results = evaluator.evaluate(examples: examples) do |example|
  classifier.call(example.input_values)
end
```

## Configuration: Setting Up Your Environment

Configure DSPy with your preferred language model:

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
config.lm = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: ENV['ANTHROPIC_API_KEY'])

# Per-module language model configuration
predictor = DSPy::Predict.new(ClassifyText)
predictor.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o')  # Override global LM for this instance
end
```

### Raw Chat API

For benchmarking or using existing prompts without DSPy's structured output features, use the `raw_chat` method:

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

This is particularly useful for:
- Benchmarking monolithic prompts against modular implementations
- Gradual migration from existing prompt systems
- Quick prototyping without signatures

See the [benchmarking guide](/optimization/benchmarking-raw-prompts/) for detailed examples.

## Error Handling and Validation

DSPy provides comprehensive error handling:

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
Begin with basic Predict modules and add complexity gradually:

```ruby
# Start with this
basic_classifier = DSPy::Predict.new(ClassifyText)

# Add reasoning when needed
reasoning_classifier = DSPy::ChainOfThought.new(ClassifyText)

# Add tools for complex tasks
agent_classifier = DSPy::ReAct.new(ComplexClassification, tools: [WebSearch.new])
```

### 2. Use Clear Descriptions
Your signature descriptions directly impact LLM performance:

```ruby
# Good: Clear and specific
description "Classify the sentiment of customer feedback as positive, negative, or neutral. Consider context and nuance."

# Bad: Vague
description "Classify text"
```

### 3. Leverage Type Safety
Use Sorbet types to catch errors early:

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

### 4. Compose Thoughtfully
Break complex workflows into reusable components:

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

- **[Signatures & Types](../../core-concepts/signatures)** - Deep dive into signature design
- **[Predictors](../../core-concepts/predictors)** - Master the different predictor types
- **[Modules & Pipelines](../../core-concepts/modules)** - Build complex workflows
- **[Examples & Validation](../../core-concepts/examples)** - Create robust training data

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

Understanding these core concepts will enable you to build reliable LLM applications with DSPy.rb. The type system keeps you safe, the modular design keeps your code clean, and the optimization tools help you achieve production-ready performance.
