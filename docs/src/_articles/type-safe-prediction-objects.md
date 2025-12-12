---
layout: blog
title: "Ship AI Features with Confidence: Type-Safe Prediction Objects"
description: "Discover how DSPy.rb's type-safe prediction objects catch integration errors before they reach production, giving you the confidence to ship AI features faster."
date: 2025-07-15
author: "Vicente Reig"
category: "Features"
reading_time: "6 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/type-safe-prediction-objects/"
image: /images/og/type-safe-prediction-objects.png
---

Building AI applications shouldn't feel like walking a tightrope. Every time you deploy a new prompt or integrate an LLM response, you're wondering: "Will this break in production?" 

DSPy.rb eliminates that anxiety with type-safe prediction objects that catch errors during development, not when your users are watching.

## The Problem: Runtime Surprises

Picture this: You're building a content classification feature. Your LLM returns a confidence score, and everything works perfectly in development. But three weeks later, the model starts returning confidence as a string `"0.95"` instead of a float `0.95`. Your production app crashes.

```ruby
# This works in development...
result = classifier.call(content: "Amazing product!")
analytics.track_confidence(result.confidence * 100)  # Boom! 💥

# TypeError: String can't be coerced into Integer
```

Sound familiar? This is the reality of working with untyped LLM outputs.

## The Solution: Know Your Data Structure

DSPy.rb prediction objects are fully typed structs that respond to both your input and output schema. When you define a signature, you get compile-time safety:

```ruby
class ContentClassifier < DSPy::Signature
  description "Classify content sentiment and confidence"
  
  input do
    const :content, String
  end
  
  output do
    const :sentiment, String
    const :confidence, Float
  end
end

# Now your prediction object is type-safe
classifier = DSPy::Predict.new(ContentClassifier)
result = classifier.call(content: "Amazing product!")

# IDE autocomplete knows these exist
result.content      # ✅ "Amazing product!" (String)
result.sentiment    # ✅ "positive" (String)  
result.confidence   # ✅ 0.95 (Float)
```

## Three Ways This Saves You Time

### 1. Catch Errors During Development

With Sorbet type checking enabled, integration errors surface immediately:

```ruby
# This fails at type-check time, not runtime
def analyze_sentiment(text)
  result = classifier.call(content: text)
  
  # Sorbet catches this immediately
  result.nonexistent_field  # ❌ Type error: Method does not exist
  
  # And this type mismatch
  result.confidence + "high"  # ❌ Type error: Float + String
end
```

No more debugging mysterious crashes in production.

### 2. IDE Autocomplete That Actually Works

Your editor knows exactly what fields are available:

```ruby
result = classifier.call(content: "Great service!")

# As you type 'result.', your IDE shows:
# - content (String)
# - sentiment (String)  
# - confidence (Float)
```

No more guessing field names or digging through documentation.

### 3. Self-Documenting Code

Prediction objects serve as living documentation:

```ruby
def process_feedback(feedback_text)
  # The return type tells you everything you need to know
  result = classifier.call(content: feedback_text)
  
  # Input available for logging/debugging
  logger.info("Classified: #{result.content}")
  
  # Output fields are obvious
  if result.confidence > 0.8
    notify_team(result.sentiment)
  end
end
```

## Real-World Example: Customer Feedback Pipeline

Here's how a real customer feedback system benefits from type-safe predictions:

```ruby
class FeedbackAnalyzer < DSPy::Signature
  description "Analyze customer feedback for sentiment and urgency"
  
  input do
    const :feedback, String
    const :customer_tier, String
  end
  
  output do
    const :sentiment, String
    const :urgency_score, Float
    const :suggested_action, String
  end
end

class FeedbackProcessor
  def process(feedback_text, tier)
    # Type-safe prediction
    analysis = analyzer.call(
      feedback: feedback_text,
      customer_tier: tier
    )
    
    # All fields are typed and available
    FeedbackReport.create!(
      original_feedback: analysis.feedback,        # Input field
      customer_tier: analysis.customer_tier,      # Input field
      sentiment: analysis.sentiment,               # Output field
      urgency: analysis.urgency_score,            # Output field  
      action: analysis.suggested_action           # Output field
    )
    
    # Type-safe conditional logic
    if analysis.urgency_score > 0.8
      alert_support_team(analysis)
    end
  end
end
```

## The Hidden Benefit: Fearless Refactoring

When you need to modify your signature, the type system guides you through every change:

```ruby
# Add a new output field
class FeedbackAnalyzer < DSPy::Signature
  # ... existing fields ...
  
  output do
    const :sentiment, String
    const :urgency_score, Float
    const :suggested_action, String
    const :category, String  # 👈 New field
  end
end
```

Sorbet immediately shows you every place that needs updating. No more hunting through your codebase wondering what might break.

## Beyond Strings: Modeling Real-World Relationships

While strings work for simple examples, real applications have complex domain models. DSPy.rb signatures support rich types that model your actual business logic:

```ruby
# Define your domain with T::Struct and T::Enum
class Priority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
    Critical = new('critical')
  end
end

class TicketDetails < T::Struct
  const :category, String
  const :priority, Priority
  const :estimated_hours, Float
  const :requires_escalation, T::Boolean
end

# Use rich types in your signatures
class TicketAnalyzer < DSPy::Signature
  description "Analyze support ticket for categorization and prioritization"
  
  input do
    const :ticket_content, String
    const :customer_tier, String
  end
  
  output do
    const :details, TicketDetails
    const :confidence, Float
  end
end

# Now your predictions return structured domain objects
analyzer = DSPy::Predict.new(TicketAnalyzer)
result = analyzer.call(
  ticket_content: "Critical database outage affecting all users",
  customer_tier: "enterprise"
)

# Type-safe access to nested properties
puts result.details.priority.serialize  # "critical"
puts result.details.requires_escalation  # true
puts result.details.estimated_hours      # 4.5

# Enum methods provide rich behavior
if result.details.priority == Priority::Critical
  escalate_immediately(result)
end
```

This approach brings several benefits:

**Domain-Driven Design**: Your AI outputs use the same types as your business logic
**Validation**: Enums prevent invalid states like `priority: "super-urgent"`
**Behavior**: Rich objects can have methods, not just data
**Refactoring**: Change your domain model once, and all signatures adapt

## Getting Started

Type-safe prediction objects work out of the box with DSPy.rb. Start simple and evolve toward richer domain models:

```ruby
# 1. Start with basic types
class MySignature < DSPy::Signature
  input { const :question, String }
  output { const :answer, String }
end

# 2. Evolve to domain-specific types
class SupportTicket < T::Struct
  const :category, String
  const :urgency, Priority
end

class AdvancedSignature < DSPy::Signature
  input { const :ticket_text, String }
  output { const :analysis, SupportTicket }
end

# 3. Get type-safe results that match your domain
predictor = DSPy::Predict.new(AdvancedSignature)
result = predictor.call(ticket_text: "Login broken for all users")
puts result.analysis.urgency.serialize  # Fully typed and safe
```

## The Bottom Line

Building AI features doesn't have to be a guessing game. With DSPy.rb's type-safe prediction objects, you get:

- **Immediate feedback** on integration errors
- **IDE support** that actually understands your data
- **Self-documenting code** that's easy to maintain
- **Confidence** to ship features knowing they won't break

Stop debugging runtime errors. Start building AI applications with the confidence that comes from knowing your data structures are correct.

Ready to experience type-safe AI development? [Check out the DSPy.rb documentation](/) and never worry about unexpected LLM outputs again.