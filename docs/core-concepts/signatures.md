# Signatures & Types

Signatures define the interface between your application and language models. They specify inputs, outputs, and task descriptions in a type-safe way, forming the foundation of all DSPy operations.

## Basic Signature Structure

```ruby
class TaskSignature < DSPy::Signature
  description "Clear description of what this signature accomplishes"
  
  input do
    const :field_name, Type
  end
  
  output do
    const :result_field, ResultType
  end
end
```

## Input Definition

### Simple Types

```ruby
class BasicClassifier < DSPy::Signature
  description "Classify text into categories"
  
  input do
    const :text, String              # Required string
    const :context, T.nilable(String) # Optional string
    const :max_length, Integer       # Required integer
  end
end
```

### Complex Input Types

```ruby
class DocumentProcessor < DSPy::Signature
  description "Process documents with metadata"
  
  input do
    const :document, String
    const :metadata, T::Hash[String, T.untyped]
    const :tags, T::Array[String]
    const :priority, T.nilable(Integer)
  end
end
```

## Output Definition

### Enums for Controlled Outputs

```ruby
class SentimentAnalysis < DSPy::Signature
  description "Analyze sentiment of text"
  
  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
      Mixed = new('mixed')
    end
  end
  
  class Confidence < T::Enum
    enums do
      Low = new('low')
      Medium = new('medium')
      High = new('high')
    end
  end
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, Sentiment
    const :confidence, Confidence
    const :score, Float
    const :reasoning, T.nilable(String)
  end
end
```

### Structured Outputs

```ruby
class EntityExtraction < DSPy::Signature
  description "Extract entities and their relationships from text"
  
  class EntityType < T::Enum
    enums do
      Person = new('person')
      Organization = new('organization')
      Location = new('location')
      Date = new('date')
    end
  end
  
  class Entity < T::Struct
    const :name, String
    const :type, EntityType
    const :confidence, Float
    const :span, T::Array[Integer]  # [start, end] positions
  end
  
  class Relationship < T::Struct
    const :source, String
    const :target, String
    const :relation, String
    const :confidence, Float
  end
  
  input do
    const :text, String
    const :include_relationships, T::Boolean
  end
  
  output do
    const :entities, T::Array[Entity]
    const :relationships, T::Array[Relationship]
    const :processing_time, Float
  end
end
```

## Advanced Type Patterns

### Optional Fields with Defaults

```ruby
class ContentGeneration < DSPy::Signature
  description "Generate content with configurable parameters"
  
  input do
    const :topic, String
    const :style, T.nilable(String)    # Optional
    const :length, Integer             # Required, no default
  end
  
  output do
    const :content, String
    const :word_count, Integer
    const :readability_score, T.nilable(Float)  # May not always be calculated
  end
end
```

### Union Types

```ruby
class FlexibleAnalyzer < DSPy::Signature
  description "Analyze different types of input data"
  
  input do
    const :data, T.any(String, T::Hash[String, T.untyped], T::Array[String])
    const :analysis_type, String
  end
  
  output do
    const :result, T.any(String, T::Hash[String, T.untyped])
    const :data_type_detected, String
  end
end
```

### Generic Types

```ruby
class DataTransformer < DSPy::Signature
  description "Transform data from one format to another"
  
  input do
    const :input_data, T.untyped      # Accept any type
    const :target_format, String
  end
  
  output do
    const :transformed_data, T.untyped
    const :transformation_applied, String
    const :success, T::Boolean
  end
end
```

## Validation and Constraints

### Custom Validation

```ruby
class EmailClassifier < DSPy::Signature
  description "Classify emails with validation"
  
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
  
  # Custom validation method
  def self.validate_output(output)
    if output.confidence < 0.0 || output.confidence > 1.0
      raise DSPy::ValidationError, "Confidence must be between 0.0 and 1.0"
    end
    
    if output.priority == Priority::Urgent && output.confidence < 0.8
      raise DSPy::ValidationError, "Urgent priority requires high confidence (>= 0.8)"
    end
  end
end
```

### Field Constraints

```ruby
class ProductReview < DSPy::Signature
  description "Analyze product reviews with rating constraints"
  
  input do
    const :review_text, String
    const :product_category, String
  end
  
  output do
    const :rating, Integer           # 1-5 stars
    const :aspects, T::Hash[String, Integer]  # aspect -> rating mapping
    const :summary, String
  end
  
  def self.validate_output(output)
    unless (1..5).include?(output.rating)
      raise DSPy::ValidationError, "Rating must be between 1 and 5"
    end
    
    output.aspects.each do |aspect, rating|
      unless (1..5).include?(rating)
        raise DSPy::ValidationError, "Aspect rating for '#{aspect}' must be between 1 and 5"
      end
    end
  end
end
```

## Reusable Type Definitions

### Shared Enums

```ruby
module DSPy::Types
  class Language < T::Enum
    enums do
      English = new('en')
      Spanish = new('es')
      French = new('fr')
      German = new('de')
      Chinese = new('zh')
      Japanese = new('ja')
    end
  end
  
  class TextComplexity < T::Enum
    enums do
      Elementary = new('elementary')
      Intermediate = new('intermediate')
      Advanced = new('advanced')
      Expert = new('expert')
    end
  end
end

class TranslationTask < DSPy::Signature
  description "Translate text between languages"
  
  input do
    const :text, String
    const :source_language, DSPy::Types::Language
    const :target_language, DSPy::Types::Language
  end
  
  output do
    const :translated_text, String
    const :confidence, Float
    const :detected_complexity, DSPy::Types::TextComplexity
  end
end
```

### Shared Structs

```ruby
module DSPy::Types
  class TextMetadata < T::Struct
    const :language, Language
    const :complexity, TextComplexity
    const :word_count, Integer
    const :readability_score, T.nilable(Float)
  end
  
  class ProcessingResult < T::Struct
    const :success, T::Boolean
    const :processing_time, Float
    const :tokens_used, T.nilable(Integer)
    const :cost_estimate, T.nilable(Float)
  end
end

class TextAnalyzer < DSPy::Signature
  description "Comprehensive text analysis"
  
  input do
    const :text, String
  end
  
  output do
    const :metadata, DSPy::Types::TextMetadata
    const :summary, String
    const :key_points, T::Array[String]
    const :processing_info, DSPy::Types::ProcessingResult
  end
end
```

## Signature Composition

### Inheritance

```ruby
class BaseAnalysis < DSPy::Signature
  description "Base text analysis functionality"
  
  input do
    const :text, String
    const :include_metadata, T::Boolean
  end
  
  output do
    const :word_count, Integer
    const :character_count, Integer
  end
end

class SentimentAnalysis < BaseAnalysis
  description "Sentiment analysis with base text metrics"
  
  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end
  
  output do
    # Inherits word_count and character_count from BaseAnalysis
    const :sentiment, Sentiment
    const :confidence, Float
  end
end
```

### Mixins

```ruby
module TimestampMixin
  extend T::Sig
  
  sig { void }
  def add_timestamp_outputs
    output do
      const :processed_at, Time
      const :processing_duration, Float
    end
  end
end

class DocumentProcessor < DSPy::Signature
  include TimestampMixin
  
  description "Process documents with timestamps"
  
  input do
    const :document, String
  end
  
  output do
    const :summary, String
    # Timestamp fields added via mixin
  end
  
  add_timestamp_outputs
end
```

## Testing Signatures

### Signature Validation Tests

```ruby
RSpec.describe SentimentAnalysis do
  let(:valid_input) { { text: "I love this product!" } }
  let(:valid_output) do
    {
      sentiment: SentimentAnalysis::Sentiment::Positive,
      confidence: 0.95,
      score: 0.8,
      reasoning: "Positive language and enthusiasm"
    }
  end
  
  describe "input validation" do
    it "accepts valid input" do
      expect { SentimentAnalysis.validate_input(valid_input) }.not_to raise_error
    end
    
    it "rejects missing required fields" do
      expect { SentimentAnalysis.validate_input({}) }.to raise_error(DSPy::ValidationError)
    end
  end
  
  describe "output validation" do
    it "accepts valid output" do
      expect { SentimentAnalysis.validate_output(valid_output) }.not_to raise_error
    end
    
    it "rejects invalid confidence scores" do
      invalid_output = valid_output.merge(confidence: 1.5)
      expect { SentimentAnalysis.validate_output(invalid_output) }.to raise_error(DSPy::ValidationError)
    end
  end
end
```

### Integration Tests

```ruby
RSpec.describe "Signature Integration" do
  let(:predictor) { DSPy::Predict.new(SentimentAnalysis) }
  
  it "processes real inputs correctly" do
    result = predictor.call(text: "This is an amazing product!")
    
    expect(result.sentiment).to be_a(SentimentAnalysis::Sentiment)
    expect(result.confidence).to be_between(0.0, 1.0)
    expect(result.score).to be_a(Float)
  end
end
```

## Best Practices

### 1. Clear and Specific Descriptions

```ruby
# Good: Specific and actionable
description "Classify customer support tickets by urgency (low/medium/high) and category (technical/billing/general) based on the message content and any mentioned deadlines"

# Bad: Vague
description "Classify text"
```

### 2. Meaningful Enum Values

```ruby
# Good: Clear business meaning
class TicketPriority < T::Enum
  enums do
    CanWait = new('can_wait')           # Non-urgent, can be handled later
    Standard = new('standard')          # Normal business priority
    Urgent = new('urgent')              # Needs quick attention
    Critical = new('critical')          # Business-critical issue
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

### 3. Sensible Defaults and Optional Fields

```ruby
class ConfigurableAnalysis < DSPy::Signature
  description "Analyze text with configurable depth"
  
  input do
    const :text, String
    const :depth, T.nilable(String)           # Optional: 'shallow', 'deep'
    const :include_examples, T.nilable(T::Boolean)  # Optional: default false
    const :max_examples, T.nilable(Integer)   # Optional: only if include_examples
  end
  
  output do
    const :analysis, String
    const :confidence, Float
    const :examples, T.nilable(T::Array[String])  # Only present if requested
  end
end
```

### 4. Type Safety Over Flexibility

```ruby
# Good: Type-safe with clear constraints
class StatusUpdate < DSPy::Signature
  class Status < T::Enum
    enums do
      InProgress = new('in_progress')
      Completed = new('completed')
      Failed = new('failed')
      Cancelled = new('cancelled')
    end
  end
  
  output do
    const :status, Status
    const :progress_percentage, Integer  # 0-100
  end
end

# Bad: Too flexible, no validation
class FlexibleUpdate < DSPy::Signature
  output do
    const :status, String      # Could be anything
    const :progress, T.untyped # No type safety
  end
end
```

Signatures are the contract between your application and the language model. Well-designed signatures with proper types lead to more reliable applications, better error handling, and easier debugging.