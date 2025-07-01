# Complex Types

DSPy.rb provides support for structured data types beyond simple strings through integration with Sorbet's type system. You can use enums, structs, arrays, and hashes to create well-defined interfaces for your LLM applications.

## Overview

DSPy.rb supports:
- **Enums**: Constrained value sets with T::Enum
- **Structs**: Complex objects with T::Struct
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

