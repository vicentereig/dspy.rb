# Complex Types

DSPy.rb provides rich type support for complex data structures, enabling sophisticated input/output schemas that go beyond simple strings and numbers.

## Advanced Enum Types

### Enums with Metadata

```ruby
class Priority < T::Enum
  enums do
    Low = new('low', weight: 1, sla_hours: 72)
    Medium = new('medium', weight: 2, sla_hours: 24) 
    High = new('high', weight: 3, sla_hours: 8)
    Critical = new('critical', weight: 4, sla_hours: 2)
  end
  
  sig { returns(Integer) }
  def weight
    @weight
  end
  
  sig { returns(Integer) }
  def sla_hours
    @sla_hours
  end
end

class TicketClassifier < DSPy::Signature
  description "Classify support tickets by priority and category"
  
  input do
    const :ticket_content, String
    const :user_tier, String
  end
  
  output do
    const :priority, Priority
    const :estimated_resolution_time, Integer
  end
end
```

### Hierarchical Enums

```ruby
class Category < T::Enum
  enums do
    TechnicalBug = new('technical.bug')
    TechnicalFeature = new('technical.feature_request') 
    BillingPayment = new('billing.payment_issue')
    BillingRefund = new('billing.refund_request')
    AccountAccess = new('account.access_issue')
    AccountSettings = new('account.settings_change')
  end
  
  sig { returns(String) }
  def domain
    serialize.split('.').first
  end
  
  sig { returns(String) }
  def subdomain
    serialize.split('.').last
  end
end
```

## Structured Output Types

### Nested Structs

```ruby
class Address < T::Struct
  const :street, String
  const :city, String
  const :state, String
  const :zip_code, String
  const :country, T.nilable(String)
end

class Person < T::Struct
  const :name, String
  const :email, String
  const :age, T.nilable(Integer)
  const :address, T.nilable(Address)
end

class ContactInfo < T::Struct
  const :phone, T.nilable(String)
  const :email, String
  const :preferred_contact_method, String
end

class ExtractContactInfo < DSPy::Signature
  description "Extract structured contact information from text"
  
  input do
    const :text, String
  end
  
  output do
    const :person, Person
    const :contact_info, ContactInfo
    const :confidence, Float
  end
end
```

### Complex Collections

```ruby
class Skill < T::Struct
  const :name, String
  const :proficiency_level, Integer  # 1-10
  const :years_experience, T.nilable(Integer)
end

class WorkExperience < T::Struct
  const :company, String
  const :position, String
  const :duration_months, Integer
  const :skills_used, T::Array[String]
end

class ResumeAnalysis < DSPy::Signature
  description "Analyze resume and extract structured information"
  
  input do
    const :resume_text, String
  end
  
  output do
    const :candidate_name, String
    const :skills, T::Array[Skill]
    const :work_experience, T::Array[WorkExperience]
    const :education_level, String
    const :overall_score, Integer  # 1-100
  end
end
```

## Optional and Default Values

### Optional Fields

```ruby
class ProductReview < DSPy::Signature
  description "Analyze product reviews with optional detailed breakdown"
  
  input do
    const :review_text, String
    const :include_aspects, T.nilable(T::Boolean)  # Optional flag
  end
  
  output do
    const :overall_rating, Integer
    const :sentiment, String
    const :aspects, T.nilable(T::Hash[String, Integer])  # Only if requested
    const :reviewer_demographics, T.nilable(T::Hash[String, String])  # Optional insights
  end
end
```

### Default Values

```ruby
class AnalysisConfig < T::Struct
  const :depth, String, default: 'standard'
  const :include_confidence, T::Boolean, default: true
  const :max_suggestions, Integer, default: 5
end

class TextAnalyzer < DSPy::Signature
  description "Analyze text with configurable options"
  
  input do
    const :text, String
    const :config, AnalysisConfig, default: AnalysisConfig.new
  end
  
  output do
    const :analysis, String
    const :suggestions, T::Array[String]
    const :confidence, T.nilable(Float)  # Based on config
  end
end
```

## Union Types

### Flexible Input Types

```ruby
class FlexibleData < DSPy::Signature
  description "Process various data formats"
  
  input do
    const :data, T.any(String, T::Hash[String, T.untyped], T::Array[String])
    const :format_hint, T.nilable(String)
  end
  
  output do
    const :processed_data, String
    const :detected_format, String
    const :confidence, Float
  end
end
```

### Conditional Outputs

```ruby
class ErrorResult < T::Struct
  const :error_type, String
  const :error_message, String
  const :suggestions, T::Array[String]
end

class SuccessResult < T::Struct
  const :result, String
  const :confidence, Float
  const :metadata, T::Hash[String, T.untyped]
end

class ProcessDocument < DSPy::Signature
  description "Process document and return success or error result"
  
  input do
    const :document, String
    const :strict_mode, T::Boolean
  end
  
  output do
    const :status, String  # 'success' or 'error'
    const :result, T.any(SuccessResult, ErrorResult)
  end
end
```

## Custom Type Validation

### Advanced Validation

```ruby
class EmailAddress < T::Struct
  const :address, String
  
  sig { void }
  def validate!
    unless address.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      raise T::Sig::ArgumentError, "Invalid email format: #{address}"
    end
  end
end

class PhoneNumber < T::Struct
  const :number, String
  const :country_code, T.nilable(String)
  
  sig { void }
  def validate!
    # Remove formatting
    clean_number = number.gsub(/\D/, '')
    
    unless clean_number.length >= 10
      raise T::Sig::ArgumentError, "Phone number too short: #{number}"
    end
  end
  
  sig { returns(String) }
  def formatted
    clean = number.gsub(/\D/, '')
    "(#{clean[0..2]}) #{clean[3..5]}-#{clean[6..9]}"
  end
end

class ContactExtraction < DSPy::Signature
  description "Extract and validate contact information"
  
  input do
    const :text, String
  end
  
  output do
    const :emails, T::Array[EmailAddress]
    const :phones, T::Array[PhoneNumber]
  end
  
  # Custom validation for the signature
  def self.validate_output(output)
    # Validate each email
    output[:emails].each(&:validate!)
    
    # Validate each phone number
    output[:phones].each(&:validate!)
    
    # Business rule: at least one contact method required
    if output[:emails].empty? && output[:phones].empty?
      raise DSPy::ValidationError, "At least one contact method must be extracted"
    end
  end
end
```

### Type Coercion

```ruby
class DateRange < T::Struct
  const :start_date, Date
  const :end_date, Date
  
  sig { params(value: T.any(String, Date)).returns(Date) }
  def self.coerce_date(value)
    case value
    when Date
      value
    when String
      Date.parse(value)
    else
      raise T::Sig::ArgumentError, "Cannot coerce #{value.class} to Date"
    end
  end
  
  sig { params(start_val: T.untyped, end_val: T.untyped).returns(DateRange) }
  def self.new_with_coercion(start_val:, end_val:)
    new(
      start_date: coerce_date(start_val),
      end_date: coerce_date(end_val)
    )
  end
end

class ScheduleExtraction < DSPy::Signature
  description "Extract date ranges from text with automatic coercion"
  
  input do
    const :text, String
  end
  
  output do
    const :date_ranges, T::Array[DateRange]
    const :confidence, Float
  end
  
  # Custom output processing
  def self.process_output(raw_output)
    processed_ranges = raw_output[:date_ranges].map do |range_data|
      DateRange.new_with_coercion(
        start_val: range_data[:start_date],
        end_val: range_data[:end_date]
      )
    end
    
    {
      date_ranges: processed_ranges,
      confidence: raw_output[:confidence]
    }
  end
end
```

## Generic Types

### Parameterized Types

```ruby
class Page < T::Struct
  extend T::Sig
  extend T::Generic
  
  DataType = type_member
  
  const :items, T::Array[DataType]
  const :page_number, Integer
  const :total_pages, Integer
  const :total_items, Integer
end

class SearchResult < T::Struct
  const :title, String
  const :snippet, String
  const :url, String
  const :relevance_score, Float
end

class SearchEngine < DSPy::Signature
  description "Search and return paginated results"
  
  input do
    const :query, String
    const :page_size, Integer
    const :page_number, Integer
  end
  
  output do
    const :results, Page[SearchResult]
    const :total_time_ms, Integer
  end
end
```

### Type-safe Collections

```ruby
class TypedCollection < T::Struct
  extend T::Sig
  extend T::Generic
  
  ItemType = type_member
  
  const :items, T::Array[ItemType]
  
  sig { params(item: ItemType).void }
  def add(item)
    @items = (@items || []) + [item]
  end
  
  sig { params(block: T.proc.params(item: ItemType).returns(T::Boolean)).returns(T::Array[ItemType]) }
  def filter(&block)
    items.filter(&block)
  end
  
  sig { returns(Integer) }
  def size
    items.size
  end
end

class Product < T::Struct
  const :name, String
  const :price, Float
  const :category, String
end

class ProductCategorizer < DSPy::Signature
  description "Categorize products into typed collections"
  
  input do
    const :products_data, String  # JSON string of products
  end
  
  output do
    const :electronics, TypedCollection[Product]
    const :clothing, TypedCollection[Product]
    const :books, TypedCollection[Product]
    const :other, TypedCollection[Product]
  end
end
```

## Integration Patterns

### Database Integration

```ruby
class DatabaseRecord < T::Struct
  const :id, T.nilable(Integer)
  const :created_at, T.nilable(Time)
  const :updated_at, T.nilable(Time)
  
  sig { returns(T::Boolean) }
  def persisted?
    !id.nil?
  end
  
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_attributes
    {
      id: id,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end

class CustomerRecord < DatabaseRecord
  const :name, String
  const :email, String
  const :tier, String
  const :last_interaction, T.nilable(Time)
  
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_attributes
    super.merge({
      name: name,
      email: email,
      tier: tier,
      last_interaction: last_interaction
    })
  end
end

class CustomerAnalysis < DSPy::Signature
  description "Analyze customer data and return structured database records"
  
  input do
    const :interaction_data, String
    const :customer_history, T::Array[T::Hash[String, T.untyped]]
  end
  
  output do
    const :customer, CustomerRecord
    const :should_update, T::Boolean
    const :confidence, Float
  end
end
```

### API Integration

```ruby
class APIResponse < T::Struct
  extend T::Sig
  extend T::Generic
  
  DataType = type_member
  
  const :data, T.nilable(DataType)
  const :status_code, Integer
  const :headers, T::Hash[String, String]
  const :success, T::Boolean
  const :error_message, T.nilable(String)
  
  sig { returns(T::Boolean) }
  def success?
    success && status_code >= 200 && status_code < 300
  end
end

class WeatherData < T::Struct
  const :temperature, Float
  const :humidity, Integer
  const :conditions, String
  const :forecast, T::Array[String]
end

class WeatherIntegration < DSPy::Signature
  description "Process weather data and format for API response"
  
  input do
    const :location, String
    const :raw_weather_data, T::Hash[String, T.untyped]
  end
  
  output do
    const :weather_response, APIResponse[WeatherData]
    const :cache_duration, Integer  # Seconds
  end
end
```

## Testing Complex Types

### Type Validation Tests

```ruby
RSpec.describe ContactExtraction do
  describe "email validation" do
    it "accepts valid email addresses" do
      valid_emails = [
        "user@example.com",
        "test.email+tag@domain.co.uk",
        "user123@sub.domain.org"
      ]
      
      valid_emails.each do |email|
        email_obj = EmailAddress.new(address: email)
        expect { email_obj.validate! }.not_to raise_error
      end
    end
    
    it "rejects invalid email addresses" do
      invalid_emails = [
        "invalid.email",
        "@domain.com",
        "user@",
        "user space@domain.com"
      ]
      
      invalid_emails.each do |email|
        email_obj = EmailAddress.new(address: email)
        expect { email_obj.validate! }.to raise_error(T::Sig::ArgumentError)
      end
    end
  end
  
  describe "signature validation" do
    it "validates complete contact extraction" do
      valid_output = {
        emails: [EmailAddress.new(address: "test@example.com")],
        phones: [PhoneNumber.new(number: "555-1234", country_code: "+1")]
      }
      
      expect { ContactExtraction.validate_output(valid_output) }.not_to raise_error
    end
    
    it "requires at least one contact method" do
      empty_output = {
        emails: [],
        phones: []
      }
      
      expect { ContactExtraction.validate_output(empty_output) }.to raise_error(DSPy::ValidationError)
    end
  end
end
```

### Integration Tests

```ruby
RSpec.describe "Complex Type Integration" do
  let(:predictor) { DSPy::Predict.new(ContactExtraction) }
  
  it "processes real text and returns valid types" do
    text = "Contact John Doe at john.doe@company.com or call (555) 123-4567"
    
    result = predictor.call(text: text)
    
    expect(result.emails).to be_an(Array)
    expect(result.emails.first).to be_a(EmailAddress)
    expect(result.phones).to be_an(Array)
    expect(result.phones.first).to be_a(PhoneNumber)
    
    # Validation should pass
    expect { ContactExtraction.validate_output(result.to_h) }.not_to raise_error
  end
end
```

Complex types enable sophisticated data modeling that mirrors real-world structures, providing type safety and validation for production applications.