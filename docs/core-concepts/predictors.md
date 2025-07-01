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

# Create with custom language model
predictor = DSPy::Predict.new(ClassifyText)
predictor.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o')
end
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
      { title: "Result 1", snippet: "Information about #{query}" },
      { title: "Result 2", snippet: "More details on #{query}" }
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

## Predictor Comparison

### Performance Characteristics

| Predictor | Speed | Use Case | Token Usage |
|-----------|-------|----------|-------------|
| **Predict** | Fastest | Simple classification, extraction | Low |
| **ChainOfThought** | Moderate | Complex reasoning, analysis | Medium-High |
| **ReAct** | Slowest | Multi-step tasks, tool usage | High |

### Choosing the Right Predictor

```ruby
# Simple, fast tasks
quick_classifier = DSPy::Predict.new(SimpleClassification)

# Complex reasoning needed
analyst = DSPy::ChainOfThought.new(ComplexAnalysis)

# Multi-step tasks with external data
agent = DSPy::ReAct.new(AgentTask, tools: [tool1, tool2])
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

### 3. Use Built-in Instrumentation

```ruby
# Instrumentation is automatic - check DSPy.config.instrumentation
# Events are emitted for:
# - dspy.predict
# - dspy.chain_of_thought  
# - dspy.react

# Enable logging to see events
DSPy.configure do |config|
  config.instrumentation.enabled = true
  config.instrumentation.subscribers = ['logger']
end
```

Predictors provide the core execution capabilities for DSPy applications with built-in instrumentation and type safety.