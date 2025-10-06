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

## Using Lifecycle Callbacks with Rails Patterns

DSPy modules support Rails-style lifecycle callbacks (`before`, `after`, `around`) that work seamlessly with Rails patterns. For complete callback documentation, see the [Modules documentation](/core-concepts/modules/#lifecycle-callbacks).

### Callbacks with Service Objects

Use callbacks to add instrumentation, logging, or state management to service objects:

```ruby
# app/services/content_analyzer.rb
class ContentAnalyzer < ApplicationService
  include DSPy::Module::Callbacks

  before :log_analysis_start
  after :log_analysis_end
  around :with_performance_tracking

  def initialize
    @analyzer = DSPy::Predict.new(AnalysisSignature)
  end

  def call(content)
    @content = content
    result = @analyzer.call(content: content)

    ContentAnalysis.create!(
      content: content,
      sentiment: result.sentiment.serialize,
      topics: result.topics
    )

    Success(result)
  end

  private

  def log_analysis_start
    Rails.logger.info("Starting analysis for content: #{@content[0..50]}...")
  end

  def log_analysis_end
    Rails.logger.info("Analysis completed")
  end

  def with_performance_tracking
    start_time = Time.current

    result = yield

    duration = Time.current - start_time
    Rails.logger.info("Analysis took #{duration} seconds")

    # Track metrics in your APM
    StatsD.timing('content_analyzer.duration', duration * 1000)

    result
  end
end
```

### Callbacks with ActiveRecord Integration

Use callbacks to automatically load and save state from ActiveRecord:

```ruby
# app/models/conversation.rb
class Conversation < ApplicationRecord
  has_many :messages

  # Store conversation state as JSON
  serialize :context, JSON
end

# app/services/chatbot_service.rb
class ChatbotService < DSPy::Module
  around :manage_conversation_state

  def initialize(conversation_id:)
    super()
    @conversation_id = conversation_id
    @conversation = nil
    @predictor = DSPy::Predict.new(ChatSignature)
  end

  def forward(user_message:)
    @predictor.call(
      user_message: user_message,
      context: @conversation.context
    )
  end

  private

  def manage_conversation_state
    # Load conversation from database
    @conversation = Conversation.find(@conversation_id)

    # Execute the prediction
    result = yield

    # Update conversation state
    @conversation.messages.create!(
      role: 'user',
      content: result.user_message
    )

    @conversation.messages.create!(
      role: 'assistant',
      content: result.response
    )

    @conversation.update!(
      context: result.context,
      updated_at: Time.current
    )

    result
  end
end

# Usage in controller
class ChatController < ApplicationController
  def reply
    service = ChatbotService.new(conversation_id: params[:conversation_id])
    result = service.call(user_message: params[:message])

    render json: { response: result.response }
  end
end
```

### Callbacks with Rails Concerns

Extract reusable callback behavior into Rails concerns:

```ruby
# app/concerns/observable_dspy_module.rb
module ObservableDspyModule
  extend ActiveSupport::Concern

  included do
    before :start_observation
    after :end_observation
  end

  private

  def start_observation
    @observation = {
      started_at: Time.current,
      module_name: self.class.name
    }

    Rails.logger.info("DSPy module started: #{@observation[:module_name]}")
  end

  def end_observation
    duration = Time.current - @observation[:started_at]

    Rails.logger.info(
      "DSPy module completed: #{@observation[:module_name]} in #{duration}s"
    )

    # Send to APM
    NewRelic::Agent.record_metric(
      "DSPy/#{@observation[:module_name]}/Duration",
      duration
    )
  end
end

# Use in your modules
class ArticleAnalyzer < DSPy::Module
  include ObservableDspyModule  # Adds before/after callbacks

  def initialize
    super
    @predictor = DSPy::Predict.new(AnalysisSignature)
  end

  def forward(article:)
    @predictor.call(content: article.content)
  end
end
```

### Callbacks with Background Jobs

Use callbacks to manage job state and error tracking:

```ruby
# app/jobs/ai_analysis_job.rb
class AiAnalysisJob < ApplicationJob
  queue_as :ai_processing

  class AnalysisModule < DSPy::Module
    before :mark_job_running
    after :mark_job_completed
    around :with_error_tracking

    attr_accessor :article

    def initialize(article:)
      super()
      @article = article
      @predictor = DSPy::Predict.new(AnalysisSignature)
    end

    def forward
      @predictor.call(content: @article.content)
    end

    private

    def mark_job_running
      @article.update!(analysis_status: 'running')
    end

    def mark_job_completed
      @article.update!(analysis_status: 'completed')
    end

    def with_error_tracking
      begin
        yield
      rescue StandardError => e
        @article.update!(
          analysis_status: 'failed',
          error_message: e.message
        )

        # Report to error tracking service
        Sentry.capture_exception(e, extra: {
          article_id: @article.id,
          module: self.class.name
        })

        raise e
      end
    end
  end

  def perform(article_id)
    article = Article.find(article_id)
    module_instance = AnalysisModule.new(article: article)

    result = module_instance.call

    article.update!(
      sentiment: result.sentiment.serialize,
      topics: result.topics,
      summary: result.summary
    )
  end
end
```

### Callbacks with Rails Instrumentation

Integrate with Rails' ActiveSupport::Notifications:

```ruby
# app/services/instrumented_analyzer.rb
class InstrumentedAnalyzer < DSPy::Module
  around :with_rails_instrumentation

  def initialize
    super
    @predictor = DSPy::Predict.new(AnalysisSignature)
  end

  def forward(content:)
    @predictor.call(content: content)
  end

  private

  def with_rails_instrumentation
    ActiveSupport::Notifications.instrument(
      'dspy.analysis',
      module: self.class.name
    ) do |payload|
      start_time = Time.current

      result = yield

      payload[:duration] = Time.current - start_time
      payload[:success] = true

      result
    end
  rescue StandardError => e
    ActiveSupport::Notifications.instrument(
      'dspy.analysis.error',
      module: self.class.name,
      error: e.class.name,
      message: e.message
    )
    raise
  end
end

# Subscribe to notifications
# config/initializers/dspy_instrumentation.rb
ActiveSupport::Notifications.subscribe('dspy.analysis') do |name, start, finish, id, payload|
  Rails.logger.info("DSPy Analysis: #{payload[:module]} completed in #{payload[:duration]}s")
end

ActiveSupport::Notifications.subscribe('dspy.analysis.error') do |name, start, finish, id, payload|
  Rails.logger.error("DSPy Analysis Error: #{payload[:module]} - #{payload[:error]}: #{payload[:message]}")
end
```

### Best Practices for Rails Integration

1. **Use concerns for shared callback logic** - Extract common patterns like logging, metrics, and error handling
2. **Integrate with ActiveRecord callbacks** - Coordinate module callbacks with model lifecycle hooks
3. **Leverage Rails instrumentation** - Use ActiveSupport::Notifications for observability
4. **Handle errors gracefully** - Use `around` callbacks to catch and report errors to your error tracking service
5. **Track performance** - Use callbacks to measure and report execution time to APM tools

## Conclusion

DSPy.rb's automatic enum handling makes Rails integration straightforward. The key points:

1. **Enums are automatically deserialized** - no manual parsing needed
2. **Use `.serialize` to get string values** for database storage
3. **Compare enums properly** - use enum constants, not strings
4. **Cache AI responses** to improve performance
5. **Use service objects** for clean architecture

If you're still seeing issues with enum handling, ensure you're using the latest version of DSPy.rb (0.8.1+) which includes improved type coercion.