---
layout: blog
title: "Typed Values in DSPy.rb Predictions"
description: "How DSPy.rb converts model output into Sorbet structs, enums, arrays, and scalar values at runtime."
date: 2025-07-15
author: "Vicente Reig"
category: "Features"
reading_time: "6 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/type-safe-prediction-objects/"
image: /images/og/type-safe-prediction-objects.png
---

An LM response begins as text. Application code needs values with known shapes: a `Float`, an enum member, or a nested `T::Struct`. DSPy.rb uses the signature's output schema to perform that conversion before returning a prediction.

This is runtime validation and coercion. `DSPy::Prediction` delegates field methods dynamically, so it does not currently give Sorbet a signature-specific static return type for every predictor call.

## From Response Fields to Ruby Values

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

classifier = DSPy::Predict.new(ContentClassifier)
result = classifier.call(content: "Amazing product!")

result.sentiment  # => "positive"
result.confidence # => 0.95
```

After the adapter returns structured content, `DSPy::LM` parses it and `DSPy::Predict` constructs a `DSPy::Prediction` with the signature's output schema. The prediction converts each supplied value according to the corresponding Sorbet property. Missing required fields, values that cannot be coerced, and other schema violations raise before application code receives a successful prediction.

The prediction also retains the input values, which is useful when a caller needs the original request alongside the result:

```ruby
result.content    # => "Amazing product!"
result.sentiment  # => "positive"
result.confidence # => 0.95
```

## Nested Structs and Enums

The boundary becomes more useful when the output matches the application's domain types.

```ruby
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
```

The model still returns serialized data. DSPy.rb reconstructs `TicketDetails` and deserializes `Priority` before returning the prediction:

```ruby
analyzer = DSPy::Predict.new(TicketAnalyzer)
result = analyzer.call(
  ticket_content: "Critical database outage affecting all users",
  customer_tier: "enterprise"
)

puts result.details.priority.serialize   # => "critical"
puts result.details.requires_escalation # => true

if result.details.priority == Priority::Critical
  escalate_immediately(result)
end
```

An unknown enum value or an invalid nested field fails conversion instead of leaking an untyped hash into this code. That does not prove the model's answer is correct. It establishes that the answer has the shape the application declared.

## Serialization

`DSPy::Prediction#to_h` recursively serializes nested structs and enums. `#to_json` serializes that hash:

```ruby
result.to_h
# => {
#      ticket_content: "Critical database outage affecting all users",
#      customer_tier: "enterprise",
#      details: {
#        category: "incident",
#        priority: "critical",
#        estimated_hours: 4.5,
#        requires_escalation: true
#      },
#      confidence: 0.95
#    }
```

Use the domain objects while the prediction is in Ruby. Serialize at storage, logging, or API boundaries.

## What the Boundary Does Not Do

The signature controls conversion and validation at runtime. It does not:

- guarantee that a confidence score is calibrated;
- make an LM classification semantically correct;
- turn dynamic prediction methods into statically known Sorbet methods;
- update every caller automatically when a signature changes.

Tests and evaluation still carry those responsibilities. The prediction boundary has a narrower job: turn provider output into the Ruby values the signature declares, or reject it.
