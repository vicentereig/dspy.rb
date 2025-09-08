---
layout: docs
name: Complex Types
description: Working with enums, structs, and collections in DSPy.rb
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: Complex Types
  url: "/advanced/complex-types/"
prev:
  name: Advanced
  url: "/advanced/"
next:
  name: Multi-stage Pipelines
  url: "/advanced/pipelines/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-07-21 00:00:00 +0000
---
# Complex Types

DSPy.rb provides support for structured data types beyond simple strings through integration with Sorbet's type system. You can use enums, structs, arrays, and hashes to create well-defined interfaces for your LLM applications.

## Overview

DSPy.rb supports:
- **Enums**: Constrained value sets with T::Enum
- **Structs**: Complex objects with T::Struct
- **Union Types**: Multiple possible types with T.any()
- **Collections**: Arrays and hashes of typed elements
- **Optional Fields**: Nullable types with T.nilable
- **JSON Schema Generation**: Automatic schema creation for LLM consumption

## Enum Types

### Basic Enums

```ruby
class Sentiment < T::Enum
  enums do
    Positive = new('positive')
    Negative = new('negative')
    Neutral = new('neutral')
  end
end

class ClassifyText < DSPy::Signature
  description "Classify text sentiment"
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

# Usage
classifier = DSPy::Predict.new(ClassifyText)
result = classifier.call(text: "I love this product!")
puts result.sentiment.serialize  # => "positive"
```

### String Enum Values

```ruby
class Priority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
    Critical = new('critical')
  end
end

class TicketClassifier < DSPy::Signature
  description "Classify support ticket priority"
  
  input do
    const :ticket_content, String
  end
  
  output do
    const :priority, Priority
    const :reasoning, String
  end
end
```

### Multiple Enum Fields

```ruby
class Category < T::Enum
  enums do
    Technical = new('technical')
    Billing = new('billing')
    Account = new('account')
  end
end

class Status < T::Enum
  enums do
    Open = new('open')
    InProgress = new('in_progress')
    Resolved = new('resolved')
  end
end

class TicketAnalysis < DSPy::Signature
  description "Analyze support ticket"
  
  input do
    const :content, String
  end
  
  output do
    const :category, Category
    const :priority, Priority
    const :status, Status
  end
end
```

## Struct Types

### Basic Structs

```ruby
class ContactInfo < T::Struct
  const :name, String
  const :email, String
  const :phone, T.nilable(String)
end

class ExtractContact < DSPy::Signature
  description "Extract contact information from text"
  
  input do
    const :text, String
  end
  
  output do
    const :contact, ContactInfo
    const :confidence, Float
  end
end

# Usage
extractor = DSPy::Predict.new(ExtractContact)
result = extractor.call(text: "John Doe - john@example.com - 555-1234")

# Access struct fields
puts result.contact.name     # => "John Doe"
puts result.contact.email    # => "john@example.com"
puts result.contact.phone    # => "555-1234"
```

### Nested Structs

```ruby
class Address < T::Struct
  const :street, String
  const :city, String
  const :state, String
  const :zip_code, String
end

class Person < T::Struct
  const :name, String
  const :age, Integer
  const :address, Address
end

class ExtractPersonInfo < DSPy::Signature
  description "Extract detailed person information"
  
  input do
    const :text, String
  end
  
  output do
    const :person, Person
  end
end
```

## Collection Types

### Arrays

```ruby
class ExtractKeywords < DSPy::Signature
  description "Extract keywords from text"
  
  input do
    const :text, String
  end
  
  output do
    const :keywords, T::Array[String]
    const :count, Integer
  end
end

# Usage
extractor = DSPy::Predict.new(ExtractKeywords)
result = extractor.call(text: "Machine learning and artificial intelligence...")
puts result.keywords  # => ["machine learning", "artificial intelligence", ...]
```

### Arrays of Structs

DSPy.rb supports arrays of custom T::Struct types with automatic type coercion. When the LLM returns JSON arrays containing hash objects, DSPy.rb automatically converts them to the appropriate T::Struct instances.

```ruby
class Product < T::Struct
  const :name, String
  const :price, Float
  const :category, String
end

class ExtractProducts < DSPy::Signature
  description "Extract product information from text"
  
  input do
    const :text, String
  end
  
  output do
    const :products, T::Array[Product]
    const :total_found, Integer
  end
end

# Usage
extractor = DSPy::Predict.new(ExtractProducts)
result = extractor.call(text: "We have iPhone 15 for $999 and Samsung Galaxy for $799...")

# DSPy automatically converts the JSON response to Product structs
result.products.each do |product|
  # Each product is a proper Product struct instance
  puts "#{product.name} - $#{product.price} (#{product.category})"
end
```

#### Complex Struct Arrays

You can also use more complex structs with nested types:

```ruby
class Citation < T::Struct
  const :title, String
  const :author, String
  const :year, Integer
  const :relevance, Float
  const :tags, T::Array[String]
end

class ResearchSynthesis < DSPy::Signature
  description "Synthesize research papers on a topic"
  
  input do
    const :query, String
    const :max_results, Integer
  end
  
  output do
    const :citations, T::Array[Citation]
    const :summary, String
    const :key_findings, T::Array[String]
  end
end

# The LLM returns JSON like:
# {
#   "citations": [
#     {"title": "...", "author": "...", "year": 2023, "relevance": 0.95, "tags": ["ML", "NLP"]},
#     {"title": "...", "author": "...", "year": 2022, "relevance": 0.87, "tags": ["AI"]}
#   ],
#   "summary": "...",
#   "key_findings": ["...", "..."]
# }

# DSPy automatically converts each citation hash to a Citation struct
synthesizer = DSPy::Predict.new(ResearchSynthesis)
result = synthesizer.call(query: "transformer architectures", max_results: 5)

result.citations.each do |citation|
  # citation is a Citation struct, not a hash
  puts "#{citation.title} by #{citation.author} (#{citation.year})"
  puts "Relevance: #{(citation.relevance * 100).round}%"
  puts "Tags: #{citation.tags.join(', ')}"
end
```

### Hash Types

```ruby
class AnalyzeMetrics < DSPy::Signature
  description "Analyze text and return metrics"
  
  input do
    const :text, String
  end
  
  output do
    const :metrics, T::Hash[String, Float]
    const :summary, String
  end
end

# Results in metrics like:
# { "readability" => 0.8, "sentiment_score" => 0.6, "complexity" => 0.4 }
```

## Optional and Nullable Types

### Optional Fields

```ruby
class ProductInfo < T::Struct
  const :name, String
  const :price, T.nilable(Float)      # Optional price
  const :description, T.nilable(String) # Optional description
  const :in_stock, T::Boolean
end

class ExtractProductInfo < DSPy::Signature
  description "Extract product information, handling missing data"
  
  input do
    const :text, String
  end
  
  output do
    const :product, ProductInfo
    const :confidence, Float
  end
end

# Handles cases where price or description might not be available
```

### Complex Optional Structures

```ruby
class Review < T::Struct
  const :rating, Integer
  const :comment, String
  const :reviewer_name, T.nilable(String)
  const :verified_purchase, T::Boolean
end

class ExtractReviews < DSPy::Signature
  description "Extract product reviews from text"
  
  input do
    const :text, String
  end
  
  output do
    const :reviews, T::Array[Review]
    const :average_rating, T.nilable(Float)
  end
end
```

## Union Types

DSPy.rb supports union types using Sorbet's `T.any()` syntax, allowing fields that can accept multiple types. This is particularly useful when working with LLMs that may return different types of structured data based on the context.

### Basic Union Types

You can use `T.any()` to specify that a field can be one of several types:

```ruby
class FlexibleAnalysis < DSPy::Signature
  description "Analyze data that could be numeric or textual"
  
  input do
    const :data, String
  end
  
  output do
    # Can be either a float (for numeric data) or a string (for categories)
    const :result, T.any(Float, String)
    const :result_type, String  # "numeric" or "categorical"
  end
end

# Usage
analyzer = DSPy::Predict.new(FlexibleAnalysis)

# Numeric result
result1 = analyzer.call(data: "The average score is 85.5")
puts result1.result  # => 85.5 (Float)
puts result1.result_type  # => "numeric"

# String result
result2 = analyzer.call(data: "The category is premium")
puts result2.result  # => "premium" (String)
puts result2.result_type  # => "categorical"
```

### Union Types with Structs (Single-Field Unions)

A powerful pattern is using union types with different struct types. As of v0.11.0, DSPy.rb automatically adds a `_type` field to each struct, eliminating the need for manual discriminator fields. This makes union types much simpler to use.

```ruby
# NEW in v0.11.0: Single-field union types - no discriminator needed!

# Define specific action structs (no type field required)
module TaskActions
  class CreateTask < T::Struct
    const :title, String
    const :description, String
    const :priority, T.enum([:low, :medium, :high])
    const :due_date, T.nilable(String)
  end
  
  class UpdateTask < T::Struct
    const :task_id, String
    const :updates, T::Hash[Symbol, T.untyped]
    const :updated_fields, T::Array[String]
  end
  
  class DeleteTask < T::Struct
    const :task_id, String
    const :reason, T.nilable(String)
    const :archive, T::Boolean, default: true
  end
end

# Simple signature with single union field
class TaskActionSignature < DSPy::Signature
  description "Determine the appropriate task action from user input"
  
  input do
    const :user_request, String
    const :context, T.nilable(String)
  end
  
  output do
    # Just one field! DSPy automatically handles type detection
    const :action, T.any(
      TaskActions::CreateTask,
      TaskActions::UpdateTask,
      TaskActions::DeleteTask
    )
    const :reasoning, String
  end
end

# Usage with automatic type conversion
processor = DSPy::Predict.new(TaskActionSignature)

result = processor.call(
  user_request: "Create a new task for reviewing the Q4 report",
  context: "Project management workspace"
)

# DSPy automatically detects the type from the _type field
puts result.action.class  # => TaskActions::CreateTask
puts result.action.title  # => "Review Q4 Report"
puts result.action.priority  # => :high
puts result.reasoning  # => "User wants to create a task for Q4 review"

# Pattern matching works beautifully
case result.action
when TaskActions::CreateTask
  puts "Creating task: #{result.action.title}"
when TaskActions::UpdateTask
  puts "Updating task: #{result.action.task_id}"
when TaskActions::DeleteTask
  puts "Deleting task: #{result.action.task_id}"
end
```

### How Automatic Type Conversion Works

When DSPy.rb receives a response from the LLM for a union type field:

1. **Automatic _type Field**: DSPy adds a `_type` field to each struct's JSON schema with the struct's class name
2. **Type Detection**: When deserializing, DSPy looks for the `_type` field in the response
3. **Automatic Conversion**: It converts the Hash response to the appropriate struct instance based on `_type`

This happens automatically without any configuration needed from the developer.

#### Behind the Scenes

When the LLM returns:
```json
{
  "action": {
    "_type": "CreateTask",
    "title": "Review Q4 Report",
    "description": "Analyze quarterly results",
    "priority": "high",
    "due_date": null
  },
  "reasoning": "User wants to create a task for Q4 review"
}
```

DSPy automatically:
1. Sees `_type: "CreateTask"`
2. Finds `TaskActions::CreateTask` in the union types
3. Creates a proper `CreateTask` struct instance

### Union Types in Arrays

You can also use union types within arrays for heterogeneous collections:

```ruby
class Event < T::Struct
  abstract!
  const :timestamp, String
  const :user_id, String
end

class LoginEvent < Event
  const :ip_address, String
  const :success, T::Boolean
end

class PurchaseEvent < Event
  const :product_id, String
  const :amount, Float
  const :currency, String
end

class PageViewEvent < Event
  const :page_url, String
  const :referrer, T.nilable(String)
end

class ExtractEvents < DSPy::Signature
  description "Extract different types of events from logs"
  
  input do
    const :log_text, String
  end
  
  output do
    const :events, T::Array[T.any(LoginEvent, PurchaseEvent, PageViewEvent)]
    const :event_count, Integer
  end
end

# DSPy will automatically convert each array element to the appropriate event type
```

### Best Practices for Union Types

1. **Single-Field Unions** (v0.11.0+): Use a single `T.any()` field and let DSPy handle type detection automatically:

```ruby
# Good: Single union field
output do
  const :result, T.any(SuccessResult, ErrorResult, PendingResult)
end

# Avoid: Manual discriminator pattern (pre-v0.11.0)
output do
  const :result_type, ResultType  # No longer needed!
  const :result_data, T.any(...)
end
```

2. **Keep Unions Simple**: Limit unions to 2-4 types for better LLM comprehension and reliability.

3. **Meaningful Struct Names**: Use clear struct names as they become the `_type` value:

```ruby
# Good: Clear type names
class CreateUserAction < T::Struct
class UpdateUserAction < T::Struct
class DeleteUserAction < T::Struct

# These become _type values: "CreateUserAction", "UpdateUserAction", etc.
```

5. **Document Expected Types**: In your signature description, clearly indicate when and why different types might be returned:

```ruby
class AnalyzeContent < DSPy::Signature
  description <<~DESC
    Analyze content and return:
    - Numeric score (0-100) for measurable content
    - Descriptive category for qualitative content
    - Null if content cannot be analyzed
  DESC
  
  output do
    const :analysis, T.any(Integer, String, NilClass)
  end
end
```

## Automatic Type Conversion with DSPy::Prediction

DSPy.rb v0.9.0+ includes automatic type conversion that transforms LLM JSON responses into properly typed Ruby objects. This happens transparently when using DSPy modules.

### How It Works

1. **Schema Awareness**: DSPy::Prediction uses the signature's output schema to understand expected types
2. **Recursive Conversion**: Nested hashes are converted to their corresponding T::Struct types
3. **Enum Deserialization**: String values are automatically converted to T::Enum instances
4. **Array Handling**: Arrays of structs are converted element by element
5. **Default Values**: Missing fields use their default values from the struct definition
6. **Graceful Fallback**: If conversion fails, the original hash is preserved

### Example: Automatic Conversion in Action

```ruby
class AnalysisResult < DSPy::Signature
  class Priority < T::Enum
    enums do
      Low = new('low')
      Medium = new('medium')
      High = new('high')
    end
  end
  
  class Finding < T::Struct
    const :description, String
    const :priority, Priority
    const :tags, T::Array[String], default: []
  end
  
  output do
    const :findings, T::Array[Finding]
    const :summary, String
  end
end

# When the LLM returns:
# {
#   "findings": [
#     {"description": "Security issue", "priority": "high"},
#     {"description": "Performance issue", "priority": "low", "tags": ["optimization"]}
#   ],
#   "summary": "Found 2 issues"
# }

analyzer = DSPy::Predict.new(AnalysisResult)
result = analyzer.call(input: "analyze this code")

# Automatic conversions:
result.findings                    # => Array of Finding structs (not hashes!)
result.findings.first.priority     # => Priority::High (not "high" string!)
result.findings.first.tags        # => [] (default value applied)
result.findings.last.tags         # => ["optimization"]
```

### Conversion Features

#### 1. Deep Nesting Support

```ruby
class Company < T::Struct
  class Department < T::Struct
    class Team < T::Struct
      const :name, String
      const :size, Integer
    end
    
    const :name, String
    const :teams, T::Array[Team]
  end
  
  const :name, String
  const :departments, T::Array[Department]
end

# Nested structures are converted recursively
# Hash -> Company -> Department -> Team
```

#### 2. Union Type Handling

```ruby
# With discriminator fields
output do
  const :action_type, ActionEnum  # Discriminator
  const :details, T.any(CreateAction, UpdateAction, DeleteAction)
end

# DSPy automatically selects the correct struct type based on action_type
```

#### 3. Edge Cases

- **Missing Fields**: Use struct defaults or nil for optional fields
- **Extra Fields**: Ignored during conversion
- **Type Mismatches**: Falls back to original value
- **Invalid Enums**: Raises KeyError (handle appropriately)

### Performance Considerations

- Conversion happens once when creating the Prediction object
- Deeply nested structures (5+ levels) may impact performance
- Large arrays are converted element by element
- Consider flattening very complex structures

### Limitations

1. **Complex Union Resolution**: Without discriminators, union type selection is based on field matching
2. **Circular References**: Not supported
3. **Custom Deserializers**: Use T::Struct's built-in serialization
4. **Very Deep Nesting**: May hit recursion limits or performance issues

## Working with Complex Results

### Accessing Nested Data

```ruby
result = extractor.call(text: input_text)

# Access struct fields
person = result.person
puts "Name: #{person.name}"
puts "Address: #{person.address.street}, #{person.address.city}"

# Work with arrays
result.keywords.each_with_index do |keyword, i|
  puts "#{i+1}. #{keyword}"
end

# Process hash results
result.metrics.each do |metric, value|
  puts "#{metric}: #{value.round(2)}"
end
```

### Validation and Error Handling

```ruby
result = extractor.call(text: input_text)

# Check for nil values
if result.contact.phone
  puts "Phone: #{result.contact.phone}"
else
  puts "No phone number provided"
end

# Validate array contents
if result.products.any?
  puts "Found #{result.products.size} products"
  result.products.each do |product|
    puts "- #{product.name}: $#{product.price}"
  end
else
  puts "No products found"
end
```

## JSON Schema Integration

DSPy.rb automatically generates JSON schemas for your complex types:

```ruby
# The signature automatically creates schemas for the LLM
signature = ClassifyText.new
schema = signature.schema

# Schema includes type constraints:
# {
#   "input": {
#     "text": {"type": "string"}
#   },
#   "output": {
#     "sentiment": {"type": "string", "enum": ["positive", "negative", "neutral"]},
#     "confidence": {"type": "number"}
#   }
# }
```

## Best Practices

### 1. Use Descriptive Names

```ruby
# Good: Clear purpose and constraints
class TaskPriority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
    Urgent = new('urgent')
  end
end

# Good: Descriptive struct fields
class CustomerFeedback < T::Struct
  const :satisfaction_score, Integer
  const :main_complaint, T.nilable(String)
  const :would_recommend, T::Boolean
end
```

### 2. Handle Missing Data Gracefully

```ruby
class ExtractCompanyInfo < DSPy::Signature
  description "Extract company information, handling incomplete data"
  
  input do
    const :text, String
  end
  
  output do
    const :company_name, String
    const :industry, T.nilable(String)
    const :employee_count, T.nilable(Integer)
    const :founded_year, T.nilable(Integer)
    const :confidence, Float
  end
end

# Usage with error handling
result = extractor.call(text: company_description)

company_info = {
  name: result.company_name,
  industry: result.industry || "Unknown",
  size: result.employee_count || "Not specified",
  age: result.founded_year ? Date.current.year - result.founded_year : nil
}
```

### 3. Use Validation in Your Logic

```ruby
def process_extraction_result(result)
  # Validate required fields
  return nil unless result.contact.name.present?
  return nil unless result.contact.email.present?
  
  # Process optional fields carefully
  contact_info = {
    name: result.contact.name,
    email: result.contact.email
  }
  
  contact_info[:phone] = result.contact.phone if result.contact.phone
  
  contact_info
end
```

### 4. Design for LLM Understanding

```ruby
# Use clear, unambiguous enum values
class ResponseType < T::Enum
  enums do
    Positive = new('positive')      # Clear
    Negative = new('negative')      # Clear
    Neutral = new('neutral')        # Clear
    # Avoid: Mixed = new('mixed')   # Ambiguous
  end
end

# Use meaningful struct field names
class EmailClassification < T::Struct
  const :is_spam, T::Boolean           # Clear boolean
  const :spam_confidence, Float        # Clear confidence measure
  const :primary_topic, String         # Clear categorization
end
```

## Limitations and Best Practices

### Nesting Depth Limitations

DSPy.rb has practical limits on nested struct complexity:

**✅ Recommended Nesting (1-2 levels):**
```ruby
class Address < T::Struct
  const :street, String
  const :city, String
  const :state, String
end

class Person < T::Struct
  const :name, String
  const :address, Address  # 2 levels total - works reliably
end
```

**⚠️ Deep Nesting (3+ levels) - Use with Caution:**
```ruby
# This creates increasingly complex JSON schemas that may:
# - Trigger OpenAI depth validation warnings (>5 levels)
# - Have type coercion issues with deeply nested T::Struct objects
# - Reduce LLM accuracy due to schema complexity

class Level3 < T::Struct
  const :level4, Level4
end

class Level2 < T::Struct
  const :level3, Level3
end

class Level1 < T::Struct
  const :level2, Level2  # 4+ levels - may fail
end
```

**❌ Avoid Excessive Nesting (5+ levels):**
- JSON schema generation works but creates complex schemas
- Type coercion may return Hash objects instead of proper T::Struct instances
- OpenAI structured outputs may reject schemas exceeding depth limits
- LLMs struggle with deeply nested output requirements

### Performance Considerations

**Schema Caching:**
DSPy.rb automatically caches JSON schemas for repeated use:
```ruby
# First call generates schema
result1 = predictor.call(input: "text")

# Second call uses cached schema (faster)
result2 = predictor.call(input: "more text")
```

**Provider Optimization:**
Different providers handle complex types differently:
- **OpenAI Structured Outputs**: Excellent for 1-3 level nesting
- **Anthropic**: Robust JSON extraction handles most complexity
- **Enhanced Prompting**: Fallback for any provider, handles simpler structures better

### Troubleshooting Complex Types

**Type Coercion Issues:**
If you get Hash objects instead of T::Struct instances:
```ruby
# Check if the issue is with deep nesting
class SimpleStruct < T::Struct
  const :field, String
end

# Test with a simple struct first
# If it works, the issue is likely nesting depth
```

**Schema Validation:**
Check schema depth warnings:
```ruby
schema = YourSignature.output_json_schema
issues = DSPy::LM::Adapters::OpenAI::SchemaConverter.validate_compatibility(schema)
puts issues  # Shows depth and complexity warnings
```

**Alternative Approaches:**
Instead of deep nesting, consider:
- Flattening complex structures
- Using separate API calls for complex data
- Breaking down into multiple simpler signatures

