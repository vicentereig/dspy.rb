---
layout: docs
title: Your First Structured AI Program
description: Building a simple Q&A system that actually works
section: getting-started
date: 2025-06-28 00:00:00 +0000
---
# Your First Structured AI Program

Build a typed question-answering program, then extend it with richer result types and tools.

## What We're Building

This tutorial starts with a small Q&A program. Its signature declares the result shape; the module runs it.

By the end, the program will:
- Has a clear, typed interface
- Return structured, validated results
- Can be tested systematically
- Represent uncertainty in its output

## Setting Up

Add DSPy.rb and configure one language model:

```ruby
# Gemfile
gem 'dspy'

# In your code
require 'dspy'

# Configure your language model
DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4', api_key: ENV['OPENAI_API_KEY'])
end
```

## Replace the Prompt String with a Task Contract

The first version hides its contract in a string:

### The Prompt String

```ruby
# What most of us start with
def ask_question(question)
  prompt = "Answer this question clearly and concisely: #{question}"
  response = llm.complete(prompt)
  
  # Hope it's in the format we expect...
  response.strip
end

# Usage - crossing fingers
answer = ask_question("What is the capital of France?")
puts answer  # "Paris" or "The capital of France is Paris." or "**Paris**" or...
```

### The Typed Program

```ruby
# Define exactly what you want
class QuestionAnswering < DSPy::Signature
  description "Answer questions accurately and concisely"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String, description: "A clear, concise answer"
    const :confidence, Float, description: "How confident are you? (0.0-1.0)"
  end
end

# Create the module
qa_system = DSPy::Predict.new(QuestionAnswering)

# Run it
result = qa_system.call(question: "What is the capital of France?")
puts result.answer      # "Paris"
puts result.confidence  # 0.95
```

## Understanding What Just Happened

### **1. Clear Interface Definition**

The `DSPy::Signature` defines exactly what goes in and what comes out:

```ruby
class QuestionAnswering < DSPy::Signature
  description "Answer questions accurately and concisely"
  
  input do
    const :question, String  # Input is always a string
  end
  
  output do
    const :answer, String, description: "A clear, concise answer"
    const :confidence, Float, description: "How confident are you? (0.0-1.0)"
  end
end
```

The signature supplies the task description and the input and output schemas used for the provider request and response validation.

### **2. Predictable Module Creation**

```ruby
qa_system = DSPy::Predict.new(QuestionAnswering)
```

`DSPy::Predict` takes the signature and creates a module that performs one prediction.

### **3. Structured Results**

```ruby
result = qa_system.call(question: "What is the capital of France?")

# You get structured data back
result.answer      # Always a string
result.confidence  # A Float; the description requests a value from 0.0 to 1.0
```

## Add Richer Result Types

Enums and optional fields make the result contract more precise:

```ruby
class SmartQuestionAnswering < DSPy::Signature
  description "Answer questions with appropriate depth and context"

  class QuestionType < T::Enum
    enums do
      Factual = new('factual')
      Analytical = new('analytical')
      Creative = new('creative')
      Unclear = new('unclear')
    end
  end

  input do
    const :question, String
    const :context, String, description: "Additional context if available"
  end

  output do
    const :answer, String, description: "A clear, appropriately detailed answer"
    const :confidence, Float, description: "Confidence level (0.0-1.0)"
    const :question_type, QuestionType
    const :sources_needed, T::Boolean, description: "Would this benefit from external sources?"
  end
end

smart_qa = DSPy::Predict.new(SmartQuestionAnswering)

# Try different types of questions
factual_result = smart_qa.call(
  question: "What is the boiling point of water?",
  context: ""
)

analytical_result = smart_qa.call(
  question: "Why did the Roman Empire fall?",
  context: "We're discussing historical patterns of civilizational decline"
)

puts factual_result.question_type     # => #<QuestionType::Factual>
puts factual_result.sources_needed    # false
puts analytical_result.question_type  # => #<QuestionType::Analytical>
puts analytical_result.sources_needed # true
```

## Advanced Sorbet Types

Let's enhance our Q&A system using more Sorbet type features:

```ruby
class AdvancedQA < DSPy::Signature
  description "Answer questions with appropriate depth and context"

  class QuestionType < T::Enum
    enums do
      Factual = new('factual')
      Analytical = new('analytical')
      Creative = new('creative')
      Unclear = new('unclear')
    end
  end

  input do
    const :question, String
    const :context, T.nilable(String), description: "Additional context if available"
    const :max_length, Integer, default: 100
  end

  output do
    const :answer, String, description: "A clear, appropriately detailed answer"
    const :confidence, Float, description: "Confidence level (0.0-1.0)"
    const :question_type, QuestionType
    const :sources_needed, T::Boolean, description: "Would this benefit from external sources?"
    const :follow_up_questions, T::Array[String], description: "Suggested follow-up questions"
  end
end

smart_qa = DSPy::Predict.new(AdvancedQA)

# The Sorbet types provide runtime validation
result = smart_qa.call(
  question: "Why did the Roman Empire fall?",
  context: "We're discussing historical patterns of civilizational decline",
  max_length: 200
)

puts result.question_type        # => #<QuestionType::Analytical>
puts result.sources_needed       # true
puts result.follow_up_questions  # ["What were the economic factors?", "How did military issues contribute?"]
```

Notice how we're using **idiomatic Ruby with full Sorbet type support**:
- `T.nilable(String)` for optional fields
- `T::Enum` for constrained values
- `T::Array[String]` for typed arrays
- `T::Boolean` for boolean validation
- `default:` for optional parameters

DSPy.rb validates these types at runtime and rejects responses that cannot be converted to the declared Ruby interface.

## Building ReAct Agents with Ruby Types

`ReAct` uses Sorbet signatures to describe Ruby tools to the model:

```ruby
# Define tools with clear Ruby interfaces and Sorbet type signatures
class WeatherTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'weather'
  tool_description "Get current weather for a location"

  # Define a response struct for type safety
  class WeatherResponse < T::Struct
    const :temperature, Float
    const :condition, String
    const :humidity, Float
    const :forecast, T::Array[T.untyped]
  end

  sig { params(location: String, units: String).returns(WeatherResponse) }
  def call(location:, units: "celsius")
    # Your weather API logic here
    WeatherResponse.new(
      temperature: 22.5,
      condition: "Partly cloudy",
      humidity: 0.65,
      forecast: []
    )
  end
end

class TravelPlanner < DSPy::Signature
  description "Plan travel itineraries using available tools"
  
  input do
    const :destination, String
    const :duration, Integer, description: "Number of days"
    const :budget, T.nilable(Float)
  end
  
  output do
    const :itinerary, String
    const :estimated_cost, Float
    const :weather_considerations, String
  end
end

# Create a ReAct agent with typed tools
planner = DSPy::ReAct.new(
  TravelPlanner,
  tools: [WeatherTool.new]
)

result = planner.call(
  destination: "Tokyo",
  duration: 5,
  budget: 2000.0
)
```

The application owns the tool implementation and its side effects. `ReAct` owns the bounded loop in which the model selects a tool or returns the final result.

## Adding Error Handling

Represent expected uncertainty in the signature. Rescue transport and configuration failures separately in application code:

```ruby
class RobustQuestionAnswering < DSPy::Signature
  description "Answer questions with error handling and uncertainty"

  class AnswerStatus < T::Enum
    enums do
      Answered = new('answered')
      Uncertain = new('uncertain')
      InsufficientInfo = new('insufficient_info')
      UnclearQuestion = new('unclear_question')
    end
  end

  input do
    const :question, String
  end

  output do
    const :answer, String, description: "Best available answer"
    const :confidence, Float, description: "Confidence level (0.0-1.0)"
    const :status, AnswerStatus
    const :clarification_needed, T.nilable(String), description: "What clarification would help?"
  end
end

robust_qa = DSPy::Predict.new(RobustQuestionAnswering)

# Test with a vague question
vague_result = robust_qa.call(question: "What about that thing?")

puts vague_result.status                 # "unclear_question"
puts vague_result.clarification_needed   # "Could you specify what 'thing' you're referring to?"
puts vague_result.confidence            # 0.1
```

## Testing Your System

RSpec can verify deterministic behavior. Use evaluation examples and metrics for model behavior that cannot be asserted as an exact string:

```ruby
# spec/qa_system_spec.rb
RSpec.describe "Question Answering System", vcr: true do
  let(:qa_system) { DSPy::Predict.new(QuestionAnswering) }

  describe "factual questions" do
    it "answers basic facts confidently", vcr: { cassette_name: "qa_basic_facts" } do
      result = qa_system.call(question: "What is 2 + 2?")
      
      expect(result.answer).to eq("4")
      expect(result.confidence).to be > 0.9
    end
    
    it "handles mathematical concepts" do
      result = qa_system.call(question: "What is the square root of 16?")
      
      expect(result.answer).to eq("4")
      expect(result.confidence).to be > 0.8
    end
  end
  
  describe "uncertain questions" do
    it "expresses appropriate uncertainty" do
      result = qa_system.call(question: "What will happen tomorrow?")
      
      expect(result.confidence).to be < 0.5
      expect(result.answer).to include("uncertain")
    end
  end
  
  describe "invalid questions" do
    it "handles nonsensical input gracefully" do
      result = qa_system.call(question: "Colorless green ideas sleep furiously")
      
      expect(result.confidence).to be < 0.3
    end
  end
end
```

## What the Program Contains

The program now has a typed task contract, a prediction module, explicit uncertainty fields, a tool boundary, and tests. Typed output validation constrains the result shape; it does not prove that the answer is correct.

## Your Next Steps

### Deepen Your Understanding
**[Core Concepts →](/dspy.rb/core-concepts/)**
*Learn about Chain of Thought, ReAct agents, and module composition*

### Compose Modules
**[Pipelines →](/dspy.rb/advanced/pipelines/)**
*Compose fixed reasoning steps with Ruby control flow*

### Add Tools
**[Toolsets →](/dspy.rb/core-concepts/toolsets/)**
*Build agents that can interact with external systems*

The signature declares the task, while `Predict` and `ReAct` choose different execution strategies. Keep known control flow in Ruby. Give the model tools when it must choose the next action, and keep permissions, budgets, errors, and termination in the surrounding application.
