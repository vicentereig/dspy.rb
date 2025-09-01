---
layout: docs
name: Predictors
description: Execution engines that generate structured results using language models
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Predictors
  url: "/core-concepts/predictors/"
nav:
  prev:
    name: Modules
    url: "/core-concepts/modules/"
  next:
    name: Examples
    url: "/core-concepts/examples/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-09 00:00:00 +0000
---
# Predictors

Predictors are the execution engines that take your signatures and generate structured results using language models. DSPy.rb provides three predictor types for different use cases.

## DSPy::Predict

The foundational predictor that executes signatures directly with the language model.

### Basic Usage

```ruby
class ClassifyText < DSPy::Signature
  description "Classify text sentiment and extract key topics"
  
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
    const :topics, T::Array[String]
    const :confidence, Float
  end
end

# Create and use the predictor
classifier = DSPy::Predict.new(ClassifyText)
result = classifier.call(text: "I absolutely love the new features in this app!")

puts result.sentiment    # => #<Sentiment::Positive>
puts result.topics       # => ["app", "features"]
puts result.confidence   # => 0.92
```

### Basic Configuration

```ruby
# Basic usage - uses global language model
predictor = DSPy::Predict.new(ClassifyText)

# Basic usage - uses global language model
predictor = DSPy::Predict.new(ClassifyText)
```

## DSPy::ChainOfThought

Adds step-by-step reasoning to improve accuracy on complex tasks. The model first generates reasoning, then produces the final answer.

### When to Use ChainOfThought

- Complex analysis requiring multiple steps
- Mathematical or logical reasoning
- Tasks where showing work improves accuracy
- When you need explainable AI decisions

### Basic Usage

```ruby
class SolveMathProblem < DSPy::Signature
  description "Solve mathematical word problems step by step"
  
  input do
    const :problem, String
  end
  
  output do
    const :answer, String
    const :solution_steps, T::Array[String]
  end
end

solver = DSPy::ChainOfThought.new(SolveMathProblem)
result = solver.call(problem: "Sarah has 15 apples. She gives 7 to her friend and buys 12 more. How many apples does she have now?")

puts result.reasoning    # => "Let me work through this step by step:\n1. Sarah starts with 15 apples\n2. She gives away 7 apples: 15 - 7 = 8 apples\n3. She buys 12 more: 8 + 12 = 20 apples\nTherefore, Sarah has 20 apples."
puts result.answer       # => "20 apples"
puts result.solution_steps # => ["Start: 15 apples", "Give away 7: 15-7=8", "Buy 12 more: 8+12=20"]
```

### Working with Reasoning

```ruby
class ComplexAnalysis < DSPy::Signature
  description "Perform business analysis with reasoning"
  
  input do
    const :scenario, String
    const :constraints, T::Array[String]
  end
  
  output do
    const :recommendation, String
    const :risks, T::Array[String]
  end
end

analyzer = DSPy::ChainOfThought.new(ComplexAnalysis)

result = analyzer.call(
  scenario: "Launching a new product in a competitive market",
  constraints: ["Limited budget", "6-month timeline"]
)

# ChainOfThought automatically adds reasoning field
puts result.reasoning
# => "Let me analyze this step by step:
#     1. Market Analysis: [analysis]
#     2. Strategy Development: [approach]
#     ..."

puts result.recommendation
# => "Launch with a focused MVP approach..."
```

## DSPy::ReAct

Combines reasoning with action - enables agents that use tools and make decisions based on external information.

### Tool Definition

```ruby
class WeatherTool < DSPy::Tools::Base
  extend T::Sig
  
  tool_name "weather"
  tool_description "Get weather information"
  
  sig { params(location: String).returns(String) }
  def call(location:)
    # Simulate weather API call
    {
      location: location,
      temperature: rand(60..85),
      condition: ['sunny', 'cloudy', 'rainy'].sample
    }.to_json
  end
end

class SearchTool < DSPy::Tools::Base
  extend T::Sig
  
  tool_name "search"
  tool_description "Search the web"
  
  sig { params(query: String).returns(String) }
  def call(query:)
    # Simulate web search
    [
      { name: "Result 1", snippet: "Information about #{query}" },
      { name: "Result 2", snippet: "More details on #{query}" }
    ].to_json
  end
end
```

### ReAct Agent Usage

```ruby
class TravelAssistant < DSPy::Signature
  description "Help users plan travel"
  
  input do
    const :destination, String
    const :interests, T::Array[String]
  end
  
  output do
    const :recommendations, String
  end
end

agent = DSPy::ReAct.new(
  TravelAssistant,
  tools: [WeatherTool.new, SearchTool.new],
  max_iterations: 5
)

result = agent.call(
  destination: "Tokyo, Japan",
  interests: ["food", "temples"]
)

# The agent will:
# 1. Think: "I need to check the weather for Tokyo"
# 2. Act: weather({"location": "Tokyo, Japan"})
# 3. Think: "Now I should search for food and temple recommendations"
# 4. Act: search({"query": "best food Tokyo"})
# 5. Think: "Based on research, I can make recommendations"
# 6. Provide final response

puts result.recommendations
# => "Visit Senso-ji Temple early morning. Try ramen at local shops in Shibuya..."

# Access the reasoning history
puts result.history
# => Array of reasoning steps, actions, and observations

puts result.iterations  # => 3
puts result.tools_used  # => ["weather", "search"]
```

### Custom Tool Integration

```ruby
class DatabaseTool < DSPy::Tools::Base
  extend T::Sig
  
  tool_name "database"
  tool_description "Query user database"
  
  sig { params(connection: T.untyped).void }
  def initialize(connection)
    super()
    @db = connection
  end
  
  sig { params(query: String).returns(String) }
  def call(query:)
    # Simple database query
    result = @db.execute(query)
    result.to_json
  end
end

class CustomerService < DSPy::Signature
  description "Provide customer service"
  
  input do
    const :customer_query, String
  end
  
  output do
    const :response, String
  end
end

service_agent = DSPy::ReAct.new(
  CustomerService,
  tools: [DatabaseTool.new(database_connection)],
  max_iterations: 3
)
```

## DSPy::CodeAct

CodeAct enables agents to write and execute Ruby code dynamically to solve complex tasks. Unlike ReAct which uses predefined tools, CodeAct generates executable Ruby code that can perform calculations, data manipulation, and complex operations.

### When to Use CodeAct

- Mathematical computations and data analysis
- Complex data transformations
- Dynamic algorithm implementation
- Tasks requiring control flow and variable storage
- Scenarios where predefined tools are insufficient

### Basic Usage

```ruby
class DataAnalysis < DSPy::Signature
  description "Analyze data using Ruby code"
  
  input do
    const :task, String
  end
  
  output do
    const :solution, String
  end
end

analyzer = DSPy::CodeAct.new(DataAnalysis, max_iterations: 5)
result = analyzer.call(task: "Calculate the average of numbers 1 through 100")

puts result.solution
# => "50.5"

# Access the execution history
puts result.history
# => Array showing step-by-step code execution

puts result.iterations     # => 2
puts result.execution_context  # => Variables and results from execution
```

### Code Execution Flow

```ruby
class MathSolver < DSPy::Signature
  description "Solve mathematical problems with Ruby code"
  
  input do
    const :problem, String
  end
  
  output do
    const :answer, String
  end
end

solver = DSPy::CodeAct.new(MathSolver, max_iterations: 10)

result = solver.call(
  problem: "Find the sum of all prime numbers less than 100"
)

# The agent will:
# 1. Think: "I need to find prime numbers less than 100"
# 2. Code: def is_prime?(n); ...; end
# 3. Execute: Method defined successfully
# 4. Think: "Now I'll find all primes and sum them"
# 5. Code: primes = (2...100).select { |n| is_prime?(n) }; primes.sum
# 6. Execute: 1060
# 7. Finish: Return the result

puts result.answer      # => "1060"
puts result.iterations  # => 3

# Examine the code execution history
result.history.each_with_index do |entry, i|
  puts "Step #{entry[:step]}:"
  puts "  Thought: #{entry[:thought]}"
  puts "  Code: #{entry[:ruby_code]}"
  puts "  Result: #{entry[:execution_result]}"
  puts "  Error: #{entry[:error_message]}" if entry[:error_message]
end
```

### Error Handling and Recovery

```ruby
class RobustCalculator < DSPy::Signature
  description "Perform calculations with error recovery"
  
  input do
    const :expression, String
  end
  
  output do
    const :result, String
  end
end

calculator = DSPy::CodeAct.new(RobustCalculator, max_iterations: 5)

result = calculator.call(expression: "Calculate factorial of 10")

# If the agent writes incorrect code, it can:
# 1. Detect the error from execution feedback
# 2. Analyze the error message
# 3. Write corrected code
# 4. Successfully complete the task

puts result.result   # => "3628800"
```

### Complex Data Processing

```ruby
class DataProcessor < DSPy::Signature
  description "Process and analyze data structures"
  
  input do
    const :data_task, String
  end
  
  output do
    const :processed_result, String
  end
end

processor = DSPy::CodeAct.new(DataProcessor, max_iterations: 8)

result = processor.call(
  data_task: "Create a hash mapping letters to their ASCII values for 'HELLO'"
)

# The agent can:
# - Create complex data structures
# - Iterate through collections
# - Apply transformations
# - Format output appropriately

puts result.processed_result
# => "{'H' => 72, 'E' => 69, 'L' => 76, 'L' => 76, 'O' => 79}"
```

## Predictor Comparison

### Performance Characteristics

| Predictor | Speed | Use Case | Token Usage |
|-----------|-------|----------|-------------|
| **Predict** | Fastest | Simple classification, extraction | Low |
| **ChainOfThought** | Moderate | Complex reasoning, analysis | Medium-High |
| **ReAct** | Slower | Multi-step tasks, tool usage | High |
| **CodeAct** | Slowest | Dynamic programming, calculations | Very High |

### Choosing the Right Predictor

```ruby
# Simple, fast tasks
quick_classifier = DSPy::Predict.new(SimpleClassification)

# Complex reasoning needed
analyst = DSPy::ChainOfThought.new(ComplexAnalysis)

# Multi-step tasks with external data
agent = DSPy::ReAct.new(AgentTask, tools: [tool1, tool2])

# Dynamic programming and calculations
programmer = DSPy::CodeAct.new(ProgrammingTask, max_iterations: 10)
```

## Error Handling

### Basic Error Handling

```ruby
class RobustPredictor
  def initialize(signature)
    @primary = DSPy::ChainOfThought.new(signature)
    @fallback = DSPy::Predict.new(signature)
  end
  
  def call(input)
    @primary.call(input)
  rescue StandardError => e
    puts "Primary predictor failed: #{e.message}"
    @fallback.call(input)
  end
end
```

### Input Validation

```ruby
class ValidatedPredictor
  def initialize(signature)
    @predictor = DSPy::Predict.new(signature)
    @signature = signature
  end
  
  def call(input)
    # Validate input structure
    @signature.input_struct_class.new(**input)
    
    # Call predictor
    @predictor.call(input)
  rescue ArgumentError => e
    raise DSPy::PredictionInvalidError.new({ input: e.message })
  end
end
```

## Prompt Optimization

### Working with Examples

```ruby
# Create predictor with examples
classifier = DSPy::Predict.new(SentimentAnalysis)

# Add few-shot examples
examples = [
  DSPy::FewShotExample.new(
    input: { text: "I love this product!" },
    output: { sentiment: "positive", confidence: 0.9 }
  ),
  DSPy::FewShotExample.new(
    input: { text: "This is terrible." },
    output: { sentiment: "negative", confidence: 0.8 }
  )
]

optimized_classifier = classifier.with_examples(examples)
```

### Custom Instructions

```ruby
# Modify instruction
predictor = DSPy::Predict.new(TextClassifier)
optimized = predictor.with_instruction(
  "You are an expert classifier. Be precise and confident."
)

result = optimized.call(text: "Sample text")
```

## Testing Predictors

### Unit Tests

```ruby
RSpec.describe DSPy::Predict do
  let(:signature) { SimpleClassification }
  let(:predictor) { described_class.new(signature) }
  
  describe "#call" do
    it "returns structured results" do
      result = predictor.call(text: "Sample text")
      
      expect(result).to respond_to(:classification)
      expect(result).to respond_to(:confidence)
    end
    
    it "validates input structure" do
      expect {
        predictor.call(invalid_field: "value")
      }.to raise_error(DSPy::PredictionInvalidError)
    end
  end
end
```

### Testing ChainOfThought

```ruby
RSpec.describe DSPy::ChainOfThought do
  let(:predictor) { described_class.new(ComplexAnalysis) }
  
  it "includes reasoning in output" do
    result = predictor.call(
      scenario: "Market expansion",
      constraints: ["Limited budget"]
    )
    
    expect(result).to respond_to(:reasoning)
    expect(result.reasoning).to be_a(String)
    expect(result.reasoning).not_to be_empty
  end
end
```

## Best Practices

### 1. Choose the Right Predictor

```ruby
# Simple extraction → Predict
email_extractor = DSPy::Predict.new(ExtractEmails)

# Complex analysis → ChainOfThought  
business_analyzer = DSPy::ChainOfThought.new(BusinessAnalysis)

# Multi-step with tools → ReAct
research_agent = DSPy::ReAct.new(ResearchTask, tools: [SearchTool.new])
```

### 2. Handle Errors Gracefully

```ruby
class ProductionPredictor
  def call(input)
    @predictor.call(input)
  rescue DSPy::PredictionInvalidError => e
    handle_validation_error(e)
  rescue StandardError => e
    handle_unexpected_error(e)
  end
end
```

### 3. Use Built-in Observability

```ruby
# Observability is automatic - configure logging to see events
# Span tracking is emitted for:
# - dspy.predict
# - dspy.chain_of_thought  
# - dspy.react
# - dspy.codeact (includes code_execution events)

# Enable logging to see events
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy)
end
```

Predictors provide the core execution capabilities for DSPy applications with built-in observability and type safety.