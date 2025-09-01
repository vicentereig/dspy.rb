---
layout: docs
name: Signatures
description: Define interfaces between your application and language models
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Signatures
  url: "/core-concepts/signatures/"
nav:
  prev:
    name: Core Concepts
    url: "/core-concepts/"
  next:
    name: Modules
    url: "/core-concepts/modules/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-07-21 00:00:00 +0000
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

## Union Types

You can use `T.any()` to specify fields that can accept multiple types:

```ruby
class FlexibleExtraction < DSPy::Signature
  description "Extract data that could be in different formats"
  
  input do
    const :text, String
  end
  
  output do
    # Value can be numeric or categorical
    const :result, T.any(Float, String)
    const :confidence, Float
  end
end
```

For more complex union types with structs and automatic type conversion, see the [Union Types section in Complex Types](/advanced/complex-types/#union-types).

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

## Default Values (New in v0.7.0)

Default values make your signatures more flexible and handle missing LLM responses gracefully:

```ruby
class SmartSearch < DSPy::Signature
  description "Search with intelligent defaults"
  
  input do
    const :query, String
    const :max_results, Integer, default: 10
    const :language, String, default: "English"
    const :include_metadata, T::Boolean, default: false
  end
  
  output do
    const :results, T::Array[String]
    const :total_found, Integer
    const :search_time_ms, Float, default: 0.0
    const :cached, T::Boolean, default: false
  end
end

# Usage - input defaults reduce boilerplate
search = DSPy::Predict.new(SmartSearch)

# Only need to provide required fields
result = search.call(query: "Ruby programming")
# max_results=10, language="English", include_metadata=false are used

# Output defaults handle missing LLM responses
# If LLM doesn't return search_time_ms or cached, defaults are applied
```

### How Default Values Work

1. **Input Defaults**: Applied when creating the input struct
   - Reduce boilerplate in your code
   - Make APIs more user-friendly
   
2. **Output Defaults**: Applied when LLM response is missing fields
   - Improve robustness when LLMs omit optional fields  
   - Prevent errors from incomplete responses

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

# Access typed outputs (automatically converted from JSON)
puts result.category              # => TextClassifier::Category::Technical (not a string!)
puts result.category.serialize    # => "technical"
puts result.confidence           # => 0.85
puts result.keywords             # => ["APIs", "technical", "document"]
```

### Automatic Type Conversion (v0.9.0+)

DSPy automatically converts LLM JSON responses to the proper Ruby types:
- **Enums**: Strings are converted to T::Enum instances
- **Structs**: Nested hashes become T::Struct objects
- **Arrays**: Elements are converted recursively
- **Defaults**: Missing fields use their default values

See [Complex Types](/advanced/complex-types/#automatic-type-conversion-with-dspy-prediction) for detailed information.

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

## Special Considerations

### Working with ChainOfThought

When using `DSPy::ChainOfThought`, be aware that it automatically adds a `:reasoning` field to your signature's output:

```ruby
# DO NOT define :reasoning in your output when using ChainOfThought
class AnalysisSignature < DSPy::Signature
  description "Analyze text sentiment"
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, String
    # :reasoning field will be added automatically by ChainOfThought
  end
end

# ChainOfThought usage
analyzer = DSPy::ChainOfThought.new(AnalysisSignature)
result = analyzer.call(text: "Great product!")

# Access both original fields and automatic reasoning
puts result.sentiment  # => "positive" 
puts result.reasoning  # => "The text uses positive language..."
```

**Important**: If you define your own `:reasoning` field in a signature that will be used with ChainOfThought, it may cause conflicts or unexpected behavior.

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