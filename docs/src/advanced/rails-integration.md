---
layout: docs
title: Rails Integration Guide
description: Seamlessly integrate DSPy.rb with Ruby on Rails applications, including
  enum handling and best practices
date: 2025-07-11 00:00:00 +0000
last_modified_at: 2025-08-13 00:00:00 +0000
---
# Rails Integration Guide

DSPy.rb is designed to work seamlessly with Ruby on Rails applications. This guide covers common integration patterns and solutions to potential issues.

## Enum Handling

One common source of confusion is how DSPy.rb handles enums in Rails applications. The good news: **DSPy automatically deserializes string values to T::Enum instances**.

### The Problem

You might see code like this in Rails applications:

```ruby
# Workaround code (NOT NEEDED)
result = OpenStruct.new(
  sub_queries: raw_result.sub_queries,
  search_strategy: raw_result.search_strategy,  # Manual enum handling
  discovered_topics: raw_result.discovered_topics,
  reasoning: raw_result.reasoning
)
```

### The Solution

DSPy.rb automatically handles enum conversion:

```ruby
class SearchStrategy < DSPy::Signature
  class Strategy < T::Enum
    enums do
      Parallel = new('parallel')
      Sequential = new('sequential')
      Hybrid = new('hybrid')
    end
  end
  
  output do
    const :strategy, Strategy
  end
end

# When LLM returns: { "strategy": "parallel" }
# DSPy automatically converts to: Strategy::Parallel
result = predictor.call(query: "search term")
puts result.strategy.class  # => SearchStrategy::Strategy::Parallel
```

### Working with ActiveRecord Enums

When integrating with ActiveRecord enums, you can map between DSPy enums and Rails enums:

```ruby
# app/models/search_result.rb
class SearchResult < ApplicationRecord
  enum :strategy, { 
    parallel: 0, 
    sequential: 1, 
    hybrid: 2 
  }
end

# app/services/search_service.rb
class SearchService
  def perform(query)
    # DSPy returns T::Enum instance
    dspy_result = @predictor.call(query: query)
    
    # Convert to Rails enum value
    SearchResult.create!(
      query: query,
      strategy: dspy_result.strategy.serialize  # Returns the string value
    )
  end
end
```

### Debugging Enum Values

If you're unsure about the enum value, use these debugging techniques:

```ruby
# Check the actual class
puts result.strategy.class
# => SearchStrategy::Strategy::Parallel

# Get the string representation
puts result.strategy.serialize
# => "parallel"

# Compare with enum values
if result.strategy == SearchStrategy::Strategy::Parallel
  # Handle parallel strategy
end

# Use case statements
case result.strategy
when SearchStrategy::Strategy::Parallel
  # Parallel logic
when SearchStrategy::Strategy::Sequential
  # Sequential logic
end
```

## Service Object Pattern

DSPy.rb works great with Rails service objects:

```ruby
# app/services/content_analyzer.rb
class ContentAnalyzer < ApplicationService
  class Analysis < DSPy::Signature
    description "Analyze content sentiment and topics"
    
    class Sentiment < T::Enum
      enums do
        Positive = new('positive')
        Negative = new('negative')
        Neutral = new('neutral')
      end
    end
    
    input do
      const :content, String
    end
    
    output do
      const :sentiment, Sentiment
      const :topics, T::Array[String]
      const :summary, String
    end
  end
  
  def initialize
    @analyzer = DSPy::Predict.new(Analysis)
  end
  
  def call(content)
    result = @analyzer.call(content: content)
    
    # Store in database
    ContentAnalysis.create!(
      content: content,
      sentiment: result.sentiment.serialize,
      topics: result.topics,
      summary: result.summary
    )
    
    Success(result)
  rescue DSPy::PredictionInvalidError => e
    Failure(e.errors)
  end
end
```

## ActiveJob Integration

Process AI tasks asynchronously:

```ruby
# app/jobs/analyze_content_job.rb
class AnalyzeContentJob < ApplicationJob
  queue_as :ai_processing
  
  def perform(article_id)
    article = Article.find(article_id)
    
    result = ContentAnalyzer.call(article.content)
    
    if result.success?
      article.update!(
        sentiment: result.value.sentiment.serialize,
        ai_summary: result.value.summary,
        topics: result.value.topics
      )
    else
      # Handle errors
      Rails.logger.error "Analysis failed: #{result.failure}"
    end
  end
end
```

## Rails Cache Integration

Cache AI responses to reduce API calls:

```ruby
class CachedPredictor
  def initialize(signature_class)
    @predictor = DSPy::Predict.new(signature_class)
  end
  
  def call(**inputs)
    cache_key = generate_cache_key(inputs)
    
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      @predictor.call(**inputs)
    end
  end
  
  private
  
  def generate_cache_key(inputs)
    [
      'dspy',
      @predictor.signature_class.name,
      Digest::SHA256.hexdigest(inputs.to_json)
    ].join(':')
  end
end
```

## Configuration in Rails

Set up DSPy in an initializer:

```ruby
# config/initializers/dspy.rb
Rails.application.config.after_initialize do
  DSPy.configure do |config|
    # Use Rails credentials for API keys
    config.lm = DSPy::LM.new(
      'openai/gpt-4o-mini',
      api_key: Rails.application.credentials.openai_api_key
    )
    
    # Configure observability based on environment
    config.logger = if Rails.env.production?
      Dry.Logger(:dspy, formatter: :json) do |logger|
        logger.add_backend(stream: Rails.root.join("log/dspy.log"))
      end
    else
      Dry.Logger(:dspy) do |logger|
        logger.add_backend(level: :debug, stream: $stdout)
      end
    end
  end
end
```

## Model Validations

Add validations for enum fields:

```ruby
class Article < ApplicationRecord
  VALID_SENTIMENTS = %w[positive negative neutral]
  
  validates :sentiment, inclusion: { in: VALID_SENTIMENTS }, allow_nil: true
  
  # Convert DSPy enum to Rails attribute
  def sentiment_from_dspy=(enum_value)
    self.sentiment = enum_value&.serialize
  end
  
  # Convert Rails attribute to DSPy enum
  def sentiment_as_enum
    return nil unless sentiment.present?
    
    ArticleAnalyzer::Analysis::Sentiment.deserialize(sentiment)
  end
end
```

## Form Helpers

Create form helpers for enum fields:

```ruby
# app/helpers/dspy_form_helper.rb
module DspyFormHelper
  def dspy_enum_select(form, field, enum_class, options = {})
    choices = enum_class.values.map do |enum_value|
      [enum_value.serialize.humanize, enum_value.serialize]
    end
    
    form.select(field, choices, options)
  end
end

# In your view
<%= form_with model: @article do |f| %>
  <%= dspy_enum_select(f, :sentiment, ArticleAnalyzer::Analysis::Sentiment) %>
<% end %>
```

## Testing with RSpec

Test your DSPy integrations:

```ruby
# spec/services/content_analyzer_spec.rb
RSpec.describe ContentAnalyzer do
  describe '#call' do
    let(:content) { "This product is amazing!" }
    
    it 'correctly deserializes enum values' do
      VCR.use_cassette('content_analyzer/positive') do
        result = described_class.call(content)
        
        expect(result).to be_success
        expect(result.value.sentiment).to be_a(ContentAnalyzer::Analysis::Sentiment)
        expect(result.value.sentiment.serialize).to eq('positive')
      end
    end
    
    it 'stores enum as string in database' do
      VCR.use_cassette('content_analyzer/positive') do
        expect {
          described_class.call(content)
        }.to change(ContentAnalysis, :count).by(1)
        
        analysis = ContentAnalysis.last
        expect(analysis.sentiment).to eq('positive')
      end
    end
  end
end
```

## Common Pitfalls and Solutions

### 1. Enum Comparison Issues

```ruby
# WRONG - comparing enum instance with string
if result.strategy == "parallel"

# CORRECT - compare with enum value
if result.strategy == Strategy::Parallel

# ALSO CORRECT - serialize for string comparison
if result.strategy.serialize == "parallel"
```

### 2. JSON Serialization

```ruby
# When returning DSPy results as JSON
class ArticlesController < ApplicationController
  def analyze
    result = ContentAnalyzer.call(params[:content])
    
    render json: {
      sentiment: result.sentiment.serialize,  # Convert enum to string
      topics: result.topics,
      summary: result.summary
    }
  end
end
```

### 3. Strong Parameters

```ruby
# Handle enum fields in strong parameters
def article_params
  params.require(:article).permit(:content).tap do |p|
    # Convert string to enum if needed
    if p[:sentiment].is_a?(String)
      p[:sentiment] = ArticleAnalyzer::Analysis::Sentiment.deserialize(p[:sentiment])
    end
  end
end
```

## Conclusion

DSPy.rb's automatic enum handling makes Rails integration straightforward. The key points:

1. **Enums are automatically deserialized** - no manual parsing needed
2. **Use `.serialize` to get string values** for database storage
3. **Compare enums properly** - use enum constants, not strings
4. **Cache AI responses** to improve performance
5. **Use service objects** for clean architecture

If you're still seeing issues with enum handling, ensure you're using the latest version of DSPy.rb (0.8.1+) which includes improved type coercion.