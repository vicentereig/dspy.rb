---
layout: docs
title: Your First Structured AI Program
description: Building a simple Q&A system that actually works
section: getting-started
date: 2025-06-28 00:00:00 +0000
---
# Your First Structured AI Program

*From prompt strings to reliable systems in 10 minutes*

## What We're Building

Instead of throwing you into complex examples, let's start with something simple but transformative: a Q&A system that actually works predictably.

By the end of this tutorial, you'll have built an AI system that:
- Has a clear, typed interface
- Returns structured, predictable results
- Can be tested systematically
- Handles errors gracefully

## Setting Up

First, let's set up DSPy.rb in your project:

```ruby
# Gemfile
gem 'dspy'

# In your code
require 'dspy'

# Configure your language model
DSPy.configure do |config|
  config.lm = DSPy::LM::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY'],
    model: "gpt-4"
  )
end
```

## The Old Way vs. The New Way

Let's start by seeing the difference between prompt engineering and structured programming:

### **The Fragile Approach**

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

### **The Structured Approach**

```ruby
# Define exactly what you want
class QuestionAnswering < DSPy::Signature
  description "Answer questions accurately and concisely"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String, desc: "A clear, concise answer"
    const :confidence, Float, desc: "How confident are you? (0.0-1.0)"
  end
end

# Create a reliable system
qa_system = DSPy::Predict.new(QuestionAnswering)

# Use it predictably
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
    const :answer, String, desc: "A clear, concise answer"
    const :confidence, Float, desc: "How confident are you? (0.0-1.0)"
  end
end
```

This signature acts like a contract—the AI system knows exactly what it should produce.

### **2. Predictable Module Creation**

```ruby
qa_system = DSPy::Predict.new(QuestionAnswering)
```

`DSPy::Predict` takes your signature and creates a module that can reliably execute that reasoning pattern.

### **3. Structured Results**

```ruby
result = qa_system.call(question: "What is the capital of France?")

# You get structured data back
result.answer      # Always a string
result.confidence  # Always a float between 0.0 and 1.0
```

## Making It More Sophisticated

Let's enhance our Q&A system to handle different types of questions:

```ruby
class SmartQuestionAnswering < DSPy::Signature
  description "Answer questions with appropriate depth and context"
  
  input do
    const :question, String
    const :context, String, desc: "Additional context if available"
  end
  
  output do
    const :answer, String, desc: "A clear, appropriately detailed answer"
    const :confidence, Float, desc: "Confidence level (0.0-1.0)"
    const :question_type, String, enum: ["factual", "analytical", "creative", "unclear"]
    const :sources_needed, T::Boolean, desc: "Would this benefit from external sources?"
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

puts factual_result.question_type     # "factual"
puts factual_result.sources_needed    # false
puts analytical_result.question_type  # "analytical" 
puts analytical_result.sources_needed # true
```

## Making It More Sophisticated with Advanced Sorbet Types

Let's enhance our Q&A system to handle different types of questions using more Sorbet types:

```ruby
class SmartQuestionAnswering < DSPy::Signature
  description "Answer questions with appropriate depth and context"
  
  input do
    const :question, String
    const :context, T.nilable(String), desc: "Additional context if available"
    const :max_length, T.nilable(Integer), default: 100
  end
  
  output do
    const :answer, String, desc: "A clear, appropriately detailed answer"
    const :confidence, Float, desc: "Confidence level (0.0-1.0)"
    const :question_type, T.any(String, Symbol), enum: [:factual, :analytical, :creative, :unclear]
    const :sources_needed, T::Boolean, desc: "Would this benefit from external sources?"
    const :follow_up_questions, T::Array[String], desc: "Suggested follow-up questions"
  end
end

smart_qa = DSPy::Predict.new(SmartQuestionAnswering)

# The Sorbet types provide runtime validation
result = smart_qa.call(
  question: "Why did the Roman Empire fall?",
  context: "We're discussing historical patterns of civilizational decline",
  max_length: 200
)

puts result.question_type        # :analytical
puts result.sources_needed       # true
puts result.follow_up_questions  # ["What were the economic factors?", "How did military issues contribute?"]
```

Notice how we're using **idiomatic Ruby with full Sorbet type support**:
- `T.nilable(String)` for optional fields
- `T.any(String, Symbol)` for flexible types
- `T::Array[String]` for typed arrays
- `T::Boolean` for boolean validation
- `enum:` for constrained values
- `default:` for optional parameters

This isn't just type checking—it's **runtime validation** that ensures your LLM responses conform to your Ruby interfaces.

## Building ReAct Agents with Ruby Types

DSPy.rb's ReAct agents also use idiomatic Ruby type definitions for tools:

```ruby
# Define tools with clear Ruby interfaces
class WeatherTool < DSPy::Tool
  description "Get current weather for a location"
  
  input do
    const :location, String, desc: "City name or coordinates"
    const :units, T.nilable(String), enum: ["celsius", "fahrenheit"], default: "celsius"
  end
  
  output do
    const :temperature, Float
    const :condition, String
    const :humidity, Float
    const :forecast, T::Array[T.untyped], desc: "Next 3 days forecast"
  end
  
  def call(location:, units: "celsius")
    # Your weather API logic here
    WeatherResponse.new(
      temperature: 22.5,
      condition: "Partly cloudy",
      humidity: 0.65,
      forecast: [...]
    )
  end
end

class TravelPlanner < DSPy::Signature
  description "Plan travel itineraries using available tools"
  
  input do
    const :destination, String
    const :duration, Integer, desc: "Number of days"
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
  signature: TravelPlanner,
  tools: [WeatherTool.new]
)

result = planner.call(
  destination: "Tokyo",
  duration: 5,
  budget: 2000.0
)
```

The beauty here is that **everything is typed Ruby**—no YAML configs, no JSON schemas, just Ruby classes with Sorbet types that provide both static analysis and runtime validation.

## Adding Error Handling

Real systems need to handle edge cases gracefully:

```ruby
class RobustQuestionAnswering < DSPy::Signature
  description "Answer questions with error handling and uncertainty"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String, desc: "Best available answer"
    const :confidence, Float, desc: "Confidence level (0.0-1.0)"
    const :status, String, enum: ["answered", "uncertain", "insufficient_info", "unclear_question"]
    const :clarification_needed, T.nilable(String), desc: "What clarification would help?"
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

Here's the beautiful part—you can now test AI behavior systematically:

```ruby
# spec/qa_system_spec.rb
RSpec.describe "Question Answering System" do
  let(:qa_system) { DSPy::Predict.new(QuestionAnswering) }
  
  describe "factual questions" do
    it "answers basic facts confidently" do
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

## What You've Accomplished

In just a few minutes, you've:

1. **Moved from strings to structure** - Clear interfaces instead of prompt manipulation
2. **Gained predictability** - Know exactly what format you'll get back
3. **Enabled systematic testing** - Can verify AI behavior like any other code
4. **Built error handling** - System degrades gracefully with uncertain inputs
5. **Created transparency** - Can see confidence levels and reasoning

## Reflection Questions

Before moving on, take a moment to think about this transformation:

**About Your Current Approach:**
- How much time do you typically spend debugging prompt formatting?
- What AI systems have you built that feel fragile or unpredictable?
- How do you currently test AI behavior in your applications?

**About This New Approach:**
- What surprises you most about structured AI programming?
- How might this change your approach to building AI features?
- What kinds of AI systems would you build if reliability wasn't a concern?

## Your Next Steps

You've just experienced the foundation of structured AI programming. From here, you can:

### **🔧 Deepen Your Understanding**
**[Core Concepts →](/foundations/)**  
*Learn about Chain of Thought, ReAct agents, and module composition*

### **🏗️ Build More Complex Systems**
**[System Building →](/systems/)**  
*Chain multiple reasoning steps into powerful workflows*

### **🤝 Create AI That Uses Tools**
**[Collaboration Patterns →](/collaboration/)**  
*Build agents that can interact with external systems*

## The Path Forward

This simple Q&A system demonstrates the fundamental shift from prompt engineering to AI programming. As you continue learning, you'll discover how to:

- **Chain reasoning steps** for complex problems
- **Build agents** that use tools effectively
- **Create self-improving systems** that optimize over time
- **Compose modules** into sophisticated applications

But the core principle remains the same: **clear interfaces, predictable behavior, systematic testing**.

---

*"Every complex AI system starts with a simple, reliable foundation. You've just built yours."*
