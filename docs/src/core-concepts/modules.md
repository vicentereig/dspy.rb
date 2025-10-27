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
    name: Module Runtime Context
    url: "/core-concepts/module-runtime-context/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-10-07 00:00:00 +0000
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

## Runtime Context Guidance

Looking for fiber-local language model overrides, lifecycle callbacks, and runtime patterns? Head over to [Module Runtime Context](/core-concepts/module-runtime-context/).


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

## Instruction Update Contract

Teleprompters such as GEPA and MIPROv2 expect predictors to expose immutable update hooks so optimizers can safely swap instructions and few-shot examples. When you build a custom module that participates in optimization:

- Implement `with_instruction(new_instruction)` and return a new instance configured with the provided instruction.
- Implement `with_examples(few_shot_examples)` when your module supports few-shot updates, also returning a new instance.

You can include `DSPy::Mixins::InstructionUpdatable` to signal this capability and surface helpful default errors during development:

```ruby
class SentimentPredictor < DSPy::Module
  include DSPy::Mixins::InstructionUpdatable

  def initialize
    super
    @predictor = DSPy::Predict.new(SentimentSignature)
  end

  def with_instruction(instruction)
    clone = self.class.new
    clone.instance_variable_set(:@predictor, @predictor.with_instruction(instruction))
    clone
  end

  def with_examples(examples)
    clone = self.class.new
    clone.instance_variable_set(:@predictor, @predictor.with_examples(examples))
    clone
  end
end
```

If a module omits these hooks, teleprompters now raise `DSPy::InstructionUpdateError` instead of mutating instance variables directly, making incompatibilities immediately visible.

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
