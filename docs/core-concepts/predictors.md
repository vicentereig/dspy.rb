# Predictors

Predictors are the execution engines that take your signatures and generate structured results using language models. DSPy.rb provides several predictor types, each optimized for different use cases.

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

### Configuration Options

```ruby
# Use a specific language model
predictor = DSPy::Predict.new(
  ClassifyText,
  lm: DSPy::LM.new('openai/gpt-4o'),
  temperature: 0.1,        # Lower temperature for consistent results
  max_tokens: 150          # Limit response length
)

# With custom prompt prefix
predictor = DSPy::Predict.new(
  ClassifyText,
  prompt_prefix: "You are an expert text analyst. Be precise and confident in your classifications."
)
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

### Advanced ChainOfThought Usage

```ruby
class ComplexAnalysis < DSPy::Signature
  description "Perform complex business analysis with detailed reasoning"
  
  input do
    const :scenario, String
    const :constraints, T::Array[String]
    const :goals, T::Array[String]
  end
  
  output do
    const :recommendation, String
    const :risks, T::Array[String]
    const :expected_outcome, String
    const :confidence_level, Float
  end
end

analyzer = DSPy::ChainOfThought.new(
  ComplexAnalysis,
  reasoning_depth: :detailed,  # :brief, :standard, :detailed
  validate_reasoning: true     # Ensure reasoning is logical
)

result = analyzer.call(
  scenario: "Launching a new product in a competitive market",
  constraints: ["Limited budget", "6-month timeline"],
  goals: ["10% market share", "Break even in year 1"]
)

# Access the reasoning process
puts result.reasoning
# => "Let me analyze this scenario systematically:
#     1. Market Analysis: [detailed analysis]
#     2. Resource Assessment: [constraint evaluation]
#     3. Strategy Development: [approach reasoning]
#     ..."

puts result.recommendation
# => "Launch with a focused MVP approach targeting early adopters..."
```

## DSPy::React

Combines reasoning with action - perfect for agents that need to use tools and make decisions based on external information.

### Tool Definition

```ruby
class WeatherTool < DSPy::Tools::Base
  def get_current_weather(location)
    # Simulate weather API call
    {
      location: location,
      temperature: rand(60..85),
      condition: ['sunny', 'cloudy', 'rainy'].sample,
      humidity: rand(30..90)
    }
  end
  
  def get_forecast(location, days = 3)
    # Simulate forecast API call
    (1..days).map do |day|
      {
        day: day,
        temperature: rand(55..90),
        condition: ['sunny', 'cloudy', 'rainy', 'partly_cloudy'].sample
      }
    end
  end
end

class SearchTool < DSPy::Tools::Base
  def web_search(query)
    # Simulate web search
    [
      { title: "Result 1", url: "https://example.com/1", snippet: "Relevant information about #{query}" },
      { title: "Result 2", url: "https://example.com/2", snippet: "More details on #{query}" }
    ]
  end
end
```

### React Agent Usage

```ruby
class TravelAssistant < DSPy::Signature
  description "Help users plan travel by researching weather, activities, and providing recommendations"
  
  input do
    const :destination, String
    const :travel_dates, String
    const :interests, T::Array[String]
  end
  
  output do
    const :recommendations, T::Array[String]
    const :weather_info, String
    const :suggested_itinerary, T::Array[String]
    const :packing_tips, T::Array[String]
  end
end

agent = DSPy::React.new(
  TravelAssistant,
  tools: [WeatherTool.new, SearchTool.new],
  max_iterations: 5,      # Maximum reasoning/action cycles
  verbose: true           # Show reasoning process
)

result = agent.call(
  destination: "Tokyo, Japan",
  travel_dates: "March 15-22, 2024",
  interests: ["food", "temples", "technology"]
)

# The agent will:
# 1. Think: "I need to check the weather for Tokyo in March"
# 2. Act: get_current_weather("Tokyo, Japan") and get_forecast("Tokyo, Japan", 7)
# 3. Think: "Now I should search for food and temple recommendations"
# 4. Act: web_search("best food Tokyo March") and web_search("temples Tokyo must visit")
# 5. Think: "Based on weather and research, I can make recommendations"
# 6. Provide final structured response

puts result.recommendations
# => ["Visit Senso-ji Temple early morning to avoid crowds", 
#     "Try ramen at Ichiran in Shibuya", ...]

puts result.weather_info
# => "Tokyo in March: mild temperatures (15-20°C), occasional rain, pack layers"
```

### Custom Tool Integration

```ruby
class DatabaseTool < DSPy::Tools::Base
  def initialize(connection)
    @db = connection
  end
  
  def query_users(criteria)
    @db.execute("SELECT * FROM users WHERE #{criteria}")
  end
  
  def get_user_history(user_id)
    @db.execute("SELECT * FROM user_history WHERE user_id = ?", user_id)
  end
end

class CustomerService < DSPy::Signature
  description "Provide customer service by looking up user information and history"
  
  input do
    const :customer_query, String
    const :customer_id, T.nilable(String)
  end
  
  output do
    const :response, String
    const :action_required, T::Boolean
    const :escalate_to_human, T::Boolean
  end
end

service_agent = DSPy::React.new(
  CustomerService,
  tools: [DatabaseTool.new(database_connection)],
  context_memory: true  # Remember previous interactions
)
```

## Predictor Comparison

### Performance Characteristics

| Predictor | Speed | Accuracy | Use Case | Token Usage |
|-----------|-------|----------|----------|-------------|
| **Predict** | Fastest | Good | Simple classification, extraction | Low |
| **ChainOfThought** | Moderate | Higher | Complex reasoning, analysis | Medium-High |
| **React** | Slowest | Highest | Multi-step tasks, tool usage | High |

### Choosing the Right Predictor

```ruby
# Simple, fast tasks
quick_classifier = DSPy::Predict.new(SimpleClassification)

# Complex reasoning needed
analyst = DSPy::ChainOfThought.new(ComplexAnalysis)

# Multi-step tasks with external data
agent = DSPy::React.new(AgentTask, tools: [tool1, tool2])
```

## Error Handling

### Graceful Degradation

```ruby
class RobustPredictor
  def initialize(signature)
    @primary = DSPy::ChainOfThought.new(signature)
    @fallback = DSPy::Predict.new(signature)
  end
  
  def call(input)
    @primary.call(input)
  rescue DSPy::LMError, DSPy::TimeoutError
    Rails.logger.warn "Primary predictor failed, using fallback"
    @fallback.call(input)
  end
end
```

### Validation and Retry

```ruby
class ValidatedPredictor
  def initialize(signature, max_retries: 3)
    @predictor = DSPy::Predict.new(signature)
    @max_retries = max_retries
  end
  
  def call(input)
    retries = 0
    
    begin
      result = @predictor.call(input)
      validate_result(result)
      result
    rescue DSPy::ValidationError => e
      retries += 1
      if retries <= @max_retries
        Rails.logger.warn "Validation failed (attempt #{retries}): #{e.message}"
        retry
      else
        raise DSPy::ValidationError, "Failed validation after #{@max_retries} retries"
      end
    end
  end
  
  private
  
  def validate_result(result)
    # Custom validation logic
    raise DSPy::ValidationError, "Invalid result" unless result_valid?(result)
  end
end
```

## Performance Optimization

### Caching

```ruby
class CachedPredictor
  def initialize(signature, cache_store: Rails.cache)
    @predictor = DSPy::Predict.new(signature)
    @cache = cache_store
  end
  
  def call(input)
    cache_key = generate_cache_key(input)
    
    @cache.fetch(cache_key, expires_in: 1.hour) do
      @predictor.call(input)
    end
  end
  
  private
  
  def generate_cache_key(input)
    "dspy:predictor:#{@predictor.signature.name}:#{Digest::MD5.hexdigest(input.to_json)}"
  end
end
```

### Async Processing

```ruby
class AsyncPredictor
  def initialize(signature)
    @predictor = DSPy::Predict.new(signature)
  end
  
  def call_async(inputs)
    Async do |task|
      inputs.map do |input|
        task.async { @predictor.call(input) }
      end.map(&:wait)
    end
  end
end

# Usage
predictor = AsyncPredictor.new(ClassifyText)
results = predictor.call_async([
  { text: "First text to classify" },
  { text: "Second text to classify" },
  { text: "Third text to classify" }
])
```

### Batch Processing

```ruby
class BatchPredictor
  def initialize(signature, batch_size: 10)
    @predictor = DSPy::Predict.new(signature)
    @batch_size = batch_size
  end
  
  def call_batch(inputs)
    inputs.each_slice(@batch_size).flat_map do |batch|
      # Process batch with context
      batch_context = build_batch_context(batch)
      
      batch.map do |input|
        @predictor.call(input.merge(context: batch_context))
      end
    end
  end
  
  private
  
  def build_batch_context(batch)
    # Build shared context for batch processing
    { batch_size: batch.size, processed_at: Time.current }
  end
end
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
    
    it "validates output types" do
      result = predictor.call(text: "Sample text")
      
      expect(result.classification).to be_a(SimpleClassification::Category)
      expect(result.confidence).to be_a(Float)
      expect(result.confidence).to be_between(0.0, 1.0)
    end
  end
end
```

### Integration Tests

```ruby
RSpec.describe "Predictor Integration" do
  let(:predictor) { DSPy::ChainOfThought.new(ComplexAnalysis) }
  
  it "handles complex real-world scenarios" do
    result = predictor.call(
      scenario: "Market expansion into Asia",
      constraints: ["Limited budget", "Cultural barriers"],
      goals: ["5% market share", "Profitable in 18 months"]
    )
    
    expect(result.recommendation).to be_present
    expect(result.reasoning).to include("market")
    expect(result.risks).to be_an(Array)
    expect(result.risks).not_to be_empty
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

# Multi-step with tools → React
research_agent = DSPy::React.new(ResearchTask, tools: [SearchTool.new])
```

### 2. Handle Errors Gracefully

```ruby
class ProductionPredictor
  def call(input)
    @predictor.call(input)
  rescue DSPy::LMError => e
    handle_lm_error(e)
  rescue DSPy::ValidationError => e
    handle_validation_error(e)
  rescue StandardError => e
    handle_unexpected_error(e)
  end
end
```

### 3. Monitor Performance

```ruby
class InstrumentedPredictor
  def call(input)
    start_time = Time.current
    
    result = @predictor.call(input)
    
    DSPy.instrumentation.record_prediction(
      signature: @predictor.signature.name,
      duration: Time.current - start_time,
      tokens_used: result.metadata&.tokens_used,
      success: true
    )
    
    result
  rescue StandardError => e
    DSPy.instrumentation.record_prediction(
      signature: @predictor.signature.name,
      duration: Time.current - start_time,
      success: false,
      error: e.class.name
    )
    
    raise
  end
end
```

### 4. Optimize for Your Use Case

```ruby
# High-throughput, simple tasks
fast_classifier = DSPy::Predict.new(
  QuickClassification,
  temperature: 0.0,      # Deterministic
  max_tokens: 50         # Limit response
)

# High-accuracy, complex reasoning
thorough_analyzer = DSPy::ChainOfThought.new(
  DeepAnalysis,
  temperature: 0.3,      # Some creativity
  reasoning_depth: :detailed
)

# Autonomous agent with tools
intelligent_agent = DSPy::React.new(
  AgentTask,
  tools: comprehensive_toolset,
  max_iterations: 10,
  context_memory: true
)
```

Predictors are the workhorses of your DSPy application. Choose the right predictor for your task, handle errors gracefully, and optimize for your specific performance requirements.