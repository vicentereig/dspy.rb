---
layout: docs
name: Signatures
description: Define interfaces between your application and language models
breadcrumb:
  - name: Core Concepts
    url: /core-concepts/
  - name: Signatures
    url: /core-concepts/signatures/
nav:
  prev:
    name: Core Concepts
    url: /core-concepts/
  next:
    name: Modules
    url: /core-concepts/modules/
---

# Signatures

Signatures define the interface between your application and language models. They specify inputs, outputs, and task descriptions using Sorbet types for basic type safety.

## Basic Signature Structure

```ruby
class TaskSignature < DSPy::Signature
  description "Clear description of what this signature accomplishes"
  
  input do
    const :field_name, String
  end
  
  output do
    const :result_field, String
  end
end
```

## Input Definition

### Supported Types

```ruby
class BasicClassifier < DSPy::Signature
  description "Classify text into categories"
  
  input do
    const :text, String                    # Required string
    const :context, T.nilable(String)      # Optional string
    const :max_length, Integer             # Required integer
    const :include_score, T::Boolean       # Boolean
    const :tags, T::Array[String]          # Array of strings
    const :metadata, T::Hash[String, String] # Hash with string keys/values
  end
end
```

## Output Definition

### Using Enums for Controlled Outputs

```ruby
class SentimentAnalysis < DSPy::Signature
  description "Analyze sentiment of text"
  
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
    const :score, Float
    const :reasoning, T.nilable(String)
  end
end
```

### Using Structs for Structured Outputs

```ruby
class EntityExtraction < DSPy::Signature
  description "Extract entities from text"
  
  class EntityType < T::Enum
    enums do
      Person = new('person')
      Organization = new('organization')
      Location = new('location')
    end
  end
  
  class Entity < T::Struct
    const :name, String
    const :type, EntityType
    const :confidence, Float
  end
  
  input do
    const :text, String
  end
  
  output do
    const :entities, T::Array[Entity]
    const :total_found, Integer
  end
end
```

## Optional Fields

```ruby
class ContentGeneration < DSPy::Signature
  description "Generate content with configurable parameters"
  
  input do
    const :topic, String
    const :style, T.nilable(String)        # Optional field
    const :max_words, Integer
  end
  
  output do
    const :content, String
    const :word_count, Integer
    const :estimated_time, T.nilable(Float)  # May not always be provided
  end
end
```

## Practical Examples

### Email Classification

```ruby
class EmailClassifier < DSPy::Signature
  description "Classify emails by category and priority"
  
  class Priority < T::Enum
    enums do
      Low = new('low')
      Medium = new('medium')
      High = new('high')
      Urgent = new('urgent')
    end
  end
  
  input do
    const :email_content, String
    const :sender, String
  end
  
  output do
    const :category, String
    const :priority, Priority
    const :confidence, Float
    const :requires_action, T::Boolean
  end
end
```

### Product Review Analysis

```ruby
class ProductReview < DSPy::Signature
  description "Analyze product reviews and extract ratings"
  
  input do
    const :review_text, String
    const :product_category, String
  end
  
  output do
    const :rating, Integer
    const :summary, String
    const :key_points, T::Array[String]
  end
end
```

## Working with JSON Schema

Signatures automatically generate JSON schemas for language model integration:

```ruby
class TextClassifier < DSPy::Signature
  description "Classify text documents"
  
  class Category < T::Enum
    enums do
      Technical = new('technical')
      Business = new('business')
      Personal = new('personal')
    end
  end
  
  input do
    const :text, String
    const :length_limit, Integer
  end
  
  output do
    const :category, Category
    const :confidence, Float
    const :keywords, T::Array[String]
  end
end

# Access generated schemas
TextClassifier.input_json_schema   # Returns JSON schema for inputs
TextClassifier.output_json_schema  # Returns JSON schema for outputs
```

## Usage with Predictors

```ruby
# Use signature with a predictor
classifier = DSPy::Predict.new(TextClassifier)

# Call with input matching the signature
result = classifier.call(
  text: "This is a technical document about APIs",
  length_limit: 1000
)

# Access typed outputs
puts result.category.serialize    # => "technical"
puts result.confidence           # => 0.85
puts result.keywords             # => ["APIs", "technical", "document"]
```

## Testing Signatures

```ruby
RSpec.describe TextClassifier do
  let(:predictor) { DSPy::Predict.new(TextClassifier) }
  
  it "classifies text correctly" do
    result = predictor.call(
      text: "This is a technical document",
      length_limit: 500
    )
    
    expect(result.category).to be_a(TextClassifier::Category)
    expect(result.confidence).to be_a(Float)
    expect(result.keywords).to be_a(Array)
  end
  
  it "generates proper JSON schemas" do
    input_schema = TextClassifier.input_json_schema
    expect(input_schema[:properties]).to have_key(:text)
    expect(input_schema[:properties]).to have_key(:length_limit)
    
    output_schema = TextClassifier.output_json_schema
    expect(output_schema[:properties]).to have_key(:category)
    expect(output_schema[:properties]).to have_key(:confidence)
  end
end
```

## Best Practices

### 1. Clear and Specific Descriptions

```ruby
# Good: Specific and actionable
description "Classify customer support tickets by urgency and category based on message content"

# Bad: Vague
description "Classify text"
```

### 2. Meaningful Enum Values

```ruby
# Good: Clear business meaning
class TicketPriority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
    Urgent = new('urgent')
  end
end

# Bad: Unclear values
class Priority < T::Enum
  enums do
    P1 = new('p1')
    P2 = new('p2')
    P3 = new('p3')
  end
end
```

### 3. Use Optional Fields Appropriately

```ruby
class ConfigurableAnalysis < DSPy::Signature
  description "Analyze text with optional configuration"
  
  input do
    const :text, String
    const :include_metadata, T.nilable(T::Boolean)  # Optional
    const :max_words, T.nilable(Integer)            # Optional
  end
  
  output do
    const :analysis, String
    const :confidence, Float
    const :metadata, T.nilable(T::Hash[String, String])  # Only if requested
  end
end
```

Signatures provide the basic contract between your application and language models with type safety through Sorbet integration.