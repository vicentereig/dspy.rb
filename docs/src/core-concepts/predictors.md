---
layout: docs
title: "DSPy Predictors: Predict, ChainOfThought, and ReAct"
name: Predictors
description: "Master DSPy.rb's execution engines: Predict for simple calls, ChainOfThought for reasoning, ReAct for tool use. Each returns typed Ruby objects with full observability and error handling."
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Predictors
  url: "/core-concepts/predictors/"
nav:
  prev:
    name: Toolsets
    url: "/core-concepts/toolsets/"
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

> CodeAct now ships separately as the `dspy-code_act` gem. Install it alongside `dspy` to access Think-Code-Observe agents that synthesize and execute Ruby code.

- 📦 **Install**: `gem 'dspy-code_act', '~> 0.29'`
- 📚 **Docs**: [`lib/dspy/code_act/README.md`](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/code_act/README.md)
- 🧪 **Tests**: run via the `DSPy CodeAct` GitHub Actions job

The APIs and architectural guidance in this chapter still apply, but the implementation now evolves independently from the core gem.

## Predictor Comparison

### Performance Characteristics

| Predictor | Speed | Use Case | Token Usage | Concurrent Support |
|-----------|-------|----------|-------------|-------------------|
| **Predict** | Fastest | Simple classification, extraction | Low | ✅ Excellent |
| **ChainOfThought** | Moderate | Complex reasoning, analysis | Medium-High | ✅ Excellent |
| **ReAct** | Slower | Multi-step tasks, tool usage | High | ✅ Good |
| **CodeAct** | Slowest | Dynamic programming, calculations | Very High | ✅ Good |

### Concurrent Performance Gains

When processing multiple independent inputs, concurrent execution can provide significant speedups:

- **Simple tasks (Predict)**: 2-4x faster with 3-5 concurrent operations
- **Complex reasoning (ChainOfThought)**: 2-3x faster with moderate concurrency
- **Agent tasks (ReAct/CodeAct)**: 1.5-2.5x faster, limited by tool/code execution

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

## Concurrent Predictions

For applications that need to process multiple predictions simultaneously, DSPy.rb supports concurrent execution using Ruby's `async` gem with `Async::Barrier` for synchronization.

### When to Use Concurrent Predictions

- Processing multiple independent inputs simultaneously
- Batch operations where predictions can run in parallel
- Performance-critical applications with I/O-bound LLM calls
- Background job processing of multiple items

### Basic Concurrent Pattern

```ruby
require 'async'
require 'async/barrier'

class ContentAnalyzer < DSPy::Signature
  description "Analyze content for sentiment and topics"
  
  input do
    const :content, String
  end
  
  output do
    const :sentiment, String
    const :topics, T::Array[String]
    const :confidence, Float
  end
end

# Process multiple documents concurrently
documents = [
  "I love this new feature!",
  "The service could be better.",
  "Amazing customer support experience!"
]

analyzer = DSPy::Predict.new(ContentAnalyzer)

Async do
  barrier = Async::Barrier.new
  
  # Launch all predictions concurrently
  results = documents.map.with_index do |doc, i|
    barrier.async do
      puts "🚀 Starting analysis #{i+1} at #{Time.now.strftime('%H:%M:%S.%L')}"
      result = analyzer.call(content: doc)
      puts "✅ Completed analysis #{i+1} at #{Time.now.strftime('%H:%M:%S.%L')}"
      result
    end
  end
  
  # Wait for all to complete and collect results
  barrier.wait
  predictions = results.map(&:wait)
  
  predictions.each_with_index do |prediction, i|
    puts "Document #{i+1}: #{prediction.sentiment} (#{prediction.confidence})"
  end
end
```

### Performance Benefits

Concurrent predictions can provide significant performance improvements:

```ruby
# Sequential processing (slow)
sequential_start = Time.now
results = documents.map { |doc| analyzer.call(content: doc) }
sequential_time = Time.now - sequential_start

# Concurrent processing (fast)  
concurrent_start = Time.now
Async do
  barrier = Async::Barrier.new
  
  results = documents.map do |doc|
    barrier.async { analyzer.call(content: doc) }
  end
  
  barrier.wait
  predictions = results.map(&:wait)
end
concurrent_time = Time.now - concurrent_start

puts "Sequential: #{sequential_time.round(2)}s"
puts "Concurrent: #{concurrent_time.round(2)}s"
puts "Speedup: #{(sequential_time / concurrent_time).round(1)}x faster"
```

### Real-World Example

```ruby
# Customer service agent processing multiple requests
class CustomerService < DSPy::Signature
  description "Provide customer service response"
  
  input do
    const :customer_query, String
    const :customer_mood, String
  end
  
  output do
    const :response, String
    const :escalation_needed, T::Boolean
  end
end

customer_requests = [
  { query: "How do I reset my password?", mood: "neutral" },
  { query: "This is terrible service!", mood: "angry" },
  { query: "I love your product!", mood: "happy" },
  { query: "When will my order arrive?", mood: "concerned" }
]

service_agent = DSPy::ChainOfThought.new(CustomerService)

Async do
  barrier = Async::Barrier.new
  start_time = Time.now
  
  # Process all customer requests concurrently
  tasks = customer_requests.map.with_index do |request, i|
    barrier.async do
      service_agent.call(
        customer_query: request[:query],
        customer_mood: request[:mood]
      )
    end
  end
  
  barrier.wait
  responses = tasks.map(&:wait)
  
  total_time = Time.now - start_time
  puts "Processed #{customer_requests.length} requests in #{total_time.round(2)}s"
  
  responses.each_with_index do |response, i|
    puts "\nCustomer #{i+1}: #{customer_requests[i][:query]}"
    puts "Response: #{response.response}"
    puts "Escalation needed: #{response.escalation_needed}"
  end
end
```

### Error Handling in Concurrent Predictions

```ruby
Async do
  barrier = Async::Barrier.new
  
  tasks = documents.map.with_index do |doc, i|
    barrier.async do
      begin
        analyzer.call(content: doc)
      rescue StandardError => e
        puts "Error processing document #{i+1}: #{e.message}"
        nil  # Return nil for failed predictions
      end
    end
  end
  
  barrier.wait
  results = tasks.map(&:wait).compact  # Remove nil results
  
  puts "Successfully processed #{results.length} out of #{documents.length} documents"
end
```

### Requirements

To use concurrent predictions, add the `async` gem to your application:

```ruby
# Gemfile
gem 'async', '~> 2.29'

# In your code
require 'async'
require 'async/barrier'
```

### Best Practices for Concurrent Predictions

1. **Use Async::Barrier** for proper synchronization of multiple concurrent operations
2. **Handle errors gracefully** within each concurrent task to prevent one failure from affecting others
3. **Monitor resource usage** - concurrent predictions increase memory and network usage
4. **Consider rate limits** - some LLM providers have concurrent request limits
5. **Profile performance gains** - measure actual speedup to validate the benefits

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
