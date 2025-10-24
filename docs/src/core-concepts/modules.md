---
layout: docs
name: Modules
description: Build reusable LLM components with DSPy.rb modules
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Modules
  url: "/core-concepts/modules/"
nav:
  prev:
    name: Signatures
    url: "/core-concepts/signatures/"
  next:
    name: Predictors
    url: "/core-concepts/predictors/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-25 00:00:00 +0000
---
# Modules

DSPy.rb modules provide a foundation for building reusable LLM components. The `DSPy::Module` class serves as a base class for creating custom predictors that can be configured and tested.

## Overview

DSPy modules enable:
- **Custom Predictors**: Build specialized LLM components
- **Configuration**: Per-instance, fiber-local, and global language model configuration
- **Manual Composition**: Combine multiple modules through explicit method calls
- **Type Safety**: Sorbet integration for type-safe interfaces

## Basic Module Structure

### Creating a Custom Module

```ruby
class SentimentSignature < DSPy::Signature
  description "Analyze sentiment of text"
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, String
    const :confidence, Float
  end
end

class SentimentAnalyzer < DSPy::Module
  def initialize
    super
    
    # Create the predictor
    @predictor = DSPy::Predict.new(SentimentSignature)
  end

  def forward(text:)
    @predictor.call(text: text)
  end
end

# Usage
analyzer = SentimentAnalyzer.new
result = analyzer.call(text: "I love this product!")

puts result.sentiment    # => "positive"
puts result.confidence   # => 0.9
```

### Module with Configuration

```ruby
class ClassificationSignature < DSPy::Signature
  description "Classify text into categories"
  
  input do
    const :text, String
  end
  
  output do
    const :category, String
    const :reasoning, String
  end
end

class ConfigurableClassifier < DSPy::Module
  def initialize
    super
    
    # Create predictor
    @predictor = DSPy::ChainOfThought.new(ClassificationSignature)
  end

  def forward(text:)
    @predictor.call(text: text)
  end
end

# Usage
classifier = ConfigurableClassifier.new
result = classifier.call(text: "This is a technical document")
puts result.reasoning
```

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
classifier.config.lm = DSPy::LM.new("anthropic/claude-3-sonnet-20240229", api_key: ENV['ANTHROPIC_API_KEY'])

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

# Usage
module_instance = DerivedModule.new
result = module_instance.call(question: "Test")
# Output:
# Base setup
# Derived setup
```

### Common Use Cases

#### 1. Observability and Metrics

```ruby
class ObservableModule < DSPy::Module
  before :start_tracing
  after :end_tracing

  def initialize
    super
    @predictor = DSPy::Predict.new(QuestionSignature)
    @trace_id = nil
  end

  def forward(question:)
    @predictor.call(question: question)
  end

  private

  def start_tracing
    @trace_id = SecureRandom.uuid
    @start_time = Time.now

    # Send to APM/observability platform
    send_trace_start(@trace_id, method: "forward")
  end

  def end_tracing
    duration = Time.now - @start_time

    # Send completion to APM/observability platform
    send_trace_end(@trace_id, duration: duration)
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

## Manual Module Composition

### Sequential Processing

```ruby
class DocumentProcessor < DSPy::Module
  def initialize
    super
    
    # Create sub-modules
    @classifier = DocumentClassifier.new
    @summarizer = DocumentSummarizer.new
    @extractor = KeywordExtractor.new
  end

  def forward(document:)
    # Step 1: Classify document type
    classification = @classifier.call(content: document)
    
    # Step 2: Generate summary
    summary = @summarizer.call(content: document)
    
    # Step 3: Extract keywords
    keywords = @extractor.call(content: document)
    
    # Return combined results
    {
      document_type: classification.document_type,
      summary: summary.summary,
      keywords: keywords.keywords
    }
  end
end
```

### Conditional Processing

```ruby
class AdaptiveAnalyzer < DSPy::Module
  def initialize
    super
    
    @content_detector = ContentTypeDetector.new
    @technical_analyzer = TechnicalAnalyzer.new
    @general_analyzer = GeneralAnalyzer.new
  end

  def forward(content:)
    # Determine content type
    content_type = @content_detector.call(content: content)
    
    # Route to appropriate analyzer based on result
    if content_type.type.downcase == 'technical'
      @technical_analyzer.call(content: content)
    else
      @general_analyzer.call(content: content)
    end
  end
end
```

## Working with Different Predictors

### Module Using Chain of Thought

```ruby
class ClassificationSignature < DSPy::Signature
  description "Classify text into categories"
  
  input do
    const :text, String
  end
  
  output do
    const :category, String
    # Note: ChainOfThought automatically adds a :reasoning field
    # Do NOT define your own :reasoning field when using ChainOfThought
  end
end

class ReasoningClassifier < DSPy::Module
  def initialize
    super
    
    # ChainOfThought enhances the signature with automatic reasoning
    @predictor = DSPy::ChainOfThought.new(ClassificationSignature)
  end

  def forward(text:)
    # The result will include both :category and :reasoning fields
    @predictor.call(text: text)
  end
end

# Usage
classifier = ReasoningClassifier.new
result = classifier.call(text: "This is a technical document")

puts result.category   # => "technical"
puts result.reasoning  # => "The document mentions APIs and code examples..."
```

### Module Using ReAct for Tool Integration

```ruby
class ResearchSignature < DSPy::Signature
  description "Research assistant"
  
  input do
    const :query, String
  end
  
  output do
    const :answer, String
  end
end

class ResearchAssistant < DSPy::Module
  def initialize
    super
    
    # Use a toolset (multiple tools from one class)
    memory_tools = DSPy::Tools::MemoryToolset.to_tools
    
    # You can also create custom tools with Sorbet signatures
    # See the ReAct Agent Tutorial for custom tool examples
    
    @tools = memory_tools
    
    @predictor = DSPy::ReAct.new(ResearchSignature, tools: @tools)
  end

  def forward(query:)
    @predictor.call(query: query)
  end
end
```

### Complete Example: Personal Assistant with Memory

Here's a complete example showing how to build a personal assistant that uses memory and toolsets:

```ruby
class PersonalAssistantSignature < DSPy::Signature
  description "Personal assistant that remembers user preferences and context"
  
  input do
    const :user_message, String
    const :user_id, String
  end
  
  output do
    const :response, String
    const :action_taken, String
  end
end

class PersonalAssistant < DSPy::Module
  def initialize
    super
    
    # Get all memory tools for the agent
    memory_tools = DSPy::Tools::MemoryToolset.to_tools
    
    # Create the ReAct agent with memory capabilities
    @agent = DSPy::ReAct.new(
      PersonalAssistantSignature,
      tools: memory_tools
    )
  end
  
  def forward(user_message:, user_id:)
    # The agent can now use memory tools to:
    # - Store user preferences
    # - Retrieve past conversations
    # - Search for relevant information
    @agent.call(user_message: user_message, user_id: user_id)
  end
end

# Usage
assistant = PersonalAssistant.new

# User sets a preference
result = assistant.call(
  user_message: "I prefer dark mode for all applications",
  user_id: "user123"
)
puts result.response
# => "I've saved your preference for dark mode. I'll remember this for future recommendations."

# Later, user asks about UI preferences
result = assistant.call(
  user_message: "What UI preferences do I have?",
  user_id: "user123"
)
puts result.response
# => "Based on what you've told me, you prefer dark mode for all applications."
```

### Building a Stateful Customer Service Agent

```ruby
class CustomerServiceSignature < DSPy::Signature
  description "Customer service agent with conversation history"
  
  input do
    const :customer_query, String
    const :customer_id, String
  end
  
  output do
    const :response, String
    const :escalation_needed, T::Boolean
    const :issue_resolved, T::Boolean
  end
end

class CustomerServiceAgent < DSPy::Module
  def initialize
    super
    
    # Memory for conversation history and customer data
    memory_tools = DSPy::Tools::MemoryToolset.to_tools
    
    @agent = DSPy::ReAct.new(
      CustomerServiceSignature,
      tools: memory_tools
    )
  end
  
  def forward(customer_query:, customer_id:)
    # Agent can:
    # - Store conversation history
    # - Remember customer issues
    # - Track resolution status
    # - Access previous interactions
    result = @agent.call(
      customer_query: customer_query,
      customer_id: customer_id
    )
    
    # Store conversation for future reference
    store_conversation(customer_id, customer_query, result.response)
    
    result
  end
  
  private
  
  def store_conversation(customer_id, query, response)
    timestamp = Time.now.to_i
    DSPy::Memory.manager.store_memory(
      {
        query: query,
        response: response,
        timestamp: timestamp
      }.to_json,
      user_id: customer_id,
      tags: ["conversation", "customer_support"]
    )
  end
end

# Usage
agent = CustomerServiceAgent.new

# First interaction
result = agent.call(
  customer_query: "My order hasn't arrived and it's been 10 days",
  customer_id: "cust456"
)

# Follow-up interaction - agent remembers previous context
result = agent.call(
  customer_query: "Any update on my missing order?",
  customer_id: "cust456"
)
puts result.response
# => "I can see from our previous conversation that your order was delayed. Let me check the latest status..."
```

For more details on creating tools and toolsets, see the [Toolsets documentation](../toolsets).
For advanced memory patterns, see the [Memory Systems documentation](../../advanced/memory-systems).

### Module Using CodeAct for Dynamic Programming

CodeAct is available via the `dspy-code_act` gem. The complete Think-Code-Observe module example now lives in [`lib/dspy/code_act/README.md`](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/code_act/README.md), alongside guidance on safety, observability, and advanced usage.

## Extensibility

### Creating Custom Modules

You can create custom modules to implement your own agent systems or inference frameworks, similar to how `DSPy::ReAct` (core) or `DSPy::CodeAct` (optional gem) are built. Custom modules are ideal for:
- Building specialized agent architectures
- Implementing custom inference patterns
- Creating domain-specific processing pipelines
- Extending DSPy.rb with new capabilities

```ruby
class CustomAgentSignature < DSPy::Signature
  description "Custom agent for specialized tasks"
  
  input do
    const :task, String
    const :context, T::Hash[String, T.untyped]
  end
  
  output do
    const :result, String
    const :reasoning, String
  end
end

class CustomAgent < DSPy::Module
  def initialize
    super
    
    # Initialize your custom inference components
    @planner = DSPy::ChainOfThought.new(PlanningSignature)
    @executor = DSPy::CodeAct.new(ExecutionSignature)
    @validator = DSPy::Predict.new(ValidationSignature)
  end

  def forward(task:, context: {})
    # Implement your custom inference logic
    plan = @planner.call(task: task, context: context)
    
    execution = @executor.call(
      plan: plan.plan,
      context: context
    )
    
    validation = @validator.call(
      result: execution.solution,
      original_task: task
    )
    
    {
      result: execution.solution,
      reasoning: plan.reasoning,
      confidence: validation.confidence
    }
  end
end

# Usage
agent = CustomAgent.new
result = agent.call(
  task: "Analyze data and generate insights",
  context: { data_source: "database", format: "json" }
)
```

## Testing Modules

### Basic Module Testing

```ruby
# In your test file (using RSpec)
describe SentimentAnalyzer do
  let(:analyzer) { SentimentAnalyzer.new }

  it "analyzes sentiment" do
    result = analyzer.call(text: "I love this!")
    
    expect(result).to respond_to(:sentiment)
    expect(result).to respond_to(:confidence)
    expect(result.sentiment).to be_a(String)
    expect(result.confidence).to be_a(Float)
  end

  it "handles empty input" do
    expect {
      analyzer.call(text: "")
    }.not_to raise_error
  end
end
```

### Testing Module Composition

```ruby
describe DocumentProcessor do
  let(:processor) { DocumentProcessor.new }

  it "processes documents through all stages" do
    document = "Sample document content..."
    result = processor.call(document: document)
    
    expect(result).to have_key(:document_type)
    expect(result).to have_key(:summary)
    expect(result).to have_key(:keywords)
  end
end
```

## Best Practices

### 1. Single Responsibility

```ruby
# Good: Focused responsibility
class EmailClassifier < DSPy::Module
  def initialize
    super
    # Only handles email classification
  end

  def forward(email:)
    # Single, clear purpose
  end
end

# Good: Separate concerns through composition
class EmailProcessor < DSPy::Module
  def initialize
    super
    @classifier = EmailClassifier.new
    @spam_detector = SpamDetector.new
  end
  
  def forward(email:)
    classification = @classifier.call(email: email)
    spam_result = @spam_detector.call(email: email)
    
    { 
      classification: classification,
      spam_score: spam_result.score
    }
  end
end
```

### 2. Clear Interfaces with Signatures

```ruby
class DocumentAnalysisSignature < DSPy::Signature
  description "Analyze document content"
  
  input do
    const :content, String
  end
  
  output do
    const :main_topics, T::Array[String]
    const :word_count, Integer
  end
end

class DocumentAnalyzer < DSPy::Module
  def initialize
    super
    
    @predictor = DSPy::Predict.new(DocumentAnalysisSignature)
  end
  
  def forward(content:)
    @predictor.call(content: content)
  end
end
```

## Basic Optimization Support

Modules can work with the optimization framework through their underlying predictors:

```ruby
# Create your module
classifier = SentimentAnalyzer.new

# Use with basic optimization if available
# (Advanced optimization features are limited)
training_examples = [
  DSPy::FewShotExample.new(
    input: { text: "I love this!" },
    output: { sentiment: "positive", confidence: 0.9 }
  )
]

# Basic evaluation
result = classifier.call(text: "Test input")
```
