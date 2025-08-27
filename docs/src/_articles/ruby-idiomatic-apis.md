---
layout: blog
title: "Building Ruby-Idiomatic AI Applications with DSPy.rb"
description: "How DSPy.rb embraces Ruby conventions to make AI development feel natural. Learn about the design decisions that make DSPy.rb uniquely Ruby."
date: 2025-06-05
author: "Vicente Reig"
category: "Design"
reading_time: "8 min read"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/ruby-idiomatic-apis/"
---

When we started building DSPy.rb, we had a choice: create a direct port of the Python library or reimagine it through a Ruby lens. We chose the latter, and today I want to share how that decision shaped the library.

## The Ruby Way vs The Python Way

Let's start with a simple example. In Python's DSPy, you might write:

```python
class Sentiment(dspy.Signature):
    """Classify sentiment of text."""
    
    sentence = dspy.InputField()
    sentiment = dspy.OutputField()
```

In DSPy.rb, we embrace Ruby's block-based DSL:

```ruby
class Sentiment < DSPy::Signature
  description "Classify sentiment of text"
  
  input do
    const :sentence, String
  end
  
  output do
    const :sentiment, String
  end
end
```

Notice how the Ruby version uses blocks for grouping related fields? This isn't just aesthetic - it opens up possibilities for metaprogramming and dynamic field definitions that feel natural to Ruby developers.

## Embracing Duck Typing

Ruby developers love duck typing, and DSPy.rb tools embrace this philosophy:

```ruby
# Any object that responds to #call can be a tool
class WeatherService
  def call(location:)
    # Real implementation would call an API
    { temperature: 72, conditions: "sunny" }
  end
end

# Lambda tools for simple operations
calculator = ->(expression:) { eval(expression) }

# Even a module with a class method works
module TimeHelper
  def self.call(timezone: "UTC")
    Time.now.in_time_zone(timezone)
  end
end

# All work seamlessly with ReAct agents
agent = DSPy::ReAct.new(MySignature, tools: {
  weather: WeatherService.new,
  calculate: calculator,
  current_time: TimeHelper
})
```

This flexibility means you can integrate DSPy.rb with existing Ruby code without wrapping everything in special adapter classes.

## Enumerable All The Way Down

Ruby's Enumerable module is one of its superpowers. DSPy.rb leverages this for batch processing:

```ruby
class BatchClassifier < DSPy::Module
  def initialize
    @classifier = DSPy::Predict.new(Sentiment)
  end
  
  def process(texts)
    texts.lazy  # Process lazily for memory efficiency
         .map { |text| @classifier.call(sentence: text) }
         .select { |result| result.confidence > 0.8 }
         .group_by(&:sentiment)
         .transform_values(&:count)
  end
end

# Process thousands of reviews efficiently
classifier = BatchClassifier.new
sentiment_counts = classifier.process(reviews)
# => { positive: 1823, negative: 423, neutral: 198 }
```

## Configuration Blocks, Not YAML

While many libraries rely on YAML files, DSPy.rb uses Ruby blocks for configuration:

```ruby
DSPy.configure do |config|
  # LM configuration with nested options
  config.lm = DSPy::LM.new('openai/gpt-4o-mini') do |lm|
    lm.api_key = Rails.application.credentials.openai_api_key
    lm.temperature = 0.7
    lm.max_tokens = 1000
  end
  
  # Environment-aware logging
  config.logger = Dry.Logger(:dspy) do |logger|
    if Rails.env.production?
      logger.add_backend(formatter: :json, stream: Rails.root.join("log/dspy.log"))
    else
      logger.add_backend(level: :debug, stream: $stdout)
    end
  end
end
```

This approach provides full programmatic control and integrates naturally with Rails credentials and environment detection.

## Method Chaining (Coming Soon)

We're working on a chainable API that will feel right at home in Ruby:

```ruby
# Future API - coming in v0.8.0
result = DSPy.predict(:question_answering)
              .with_examples(training_data)
              .with_instruction("Be concise and factual")
              .with_temperature(0.3)
              .optimize_for(:accuracy)
              .cache_for(1.hour)
              .call(question: "What is Ruby?")
```

This pattern is inspired by ActiveRecord's query interface and will make complex configurations more readable.

## Type Safety Without the Ceremony

We use Sorbet for type safety, but we keep it pragmatic:

```ruby
class ArticleGenerator < DSPy::Signature
  # Simple types just work
  input do
    const :topic, String
    const :max_words, Integer, default: 500  # Defaults coming in v0.7.0
  end
  
  # Complex types are still readable
  output do
    const :title, String
    const :sections, T::Array[String]
    const :metadata, T::Hash[Symbol, T.untyped]
  end
end
```

You get type checking where it matters without verbose annotations everywhere.

## Rails Integration First-Class

DSPy.rb is designed to work seamlessly with Rails:

```ruby
# app/services/content_moderator.rb
class ContentModerator < ApplicationService
  def initialize
    @classifier = DSPy::Predict.new(ToxicityCheck)
  end
  
  def call(comment)
    Rails.cache.fetch(["toxicity", comment.cache_key], expires_in: 1.day) do
      result = @classifier.call(text: comment.body)
      
      # Integrate with ActiveRecord
      comment.update!(
        toxicity_score: result.score,
        requires_moderation: result.score > 0.7
      )
      
      # Use Rails' ActiveJob for async processing
      ModeratorNotificationJob.perform_later(comment) if result.toxic?
      
      result
    end
  end
end
```

## Introspection and Debugging

Ruby developers expect great introspection tools. DSPy.rb delivers:

```ruby
# Inspect signature fields
ArticleGenerator.input_fields.each do |name, field|
  puts "#{name}: #{field.type} (#{field.optional? ? 'optional' : 'required'})"
end

# Access full execution history
result = agent.forward(task: "Complex task")
result.history.each do |step|
  puts "Step #{step.step}: #{step.thought}"
  puts "Tools used: #{step.tool_calls.map(&:tool_name).join(', ')}"
end

# Enable detailed logging
DSPy.config.logger = Dry.Logger(:dspy) do |logger|
  logger.add_backend(level: :debug, stream: $stdout)
end
# Now you'll see every LLM call, tool execution, and timing info
```

## What's Next?

We're continuing to make DSPy.rb more Ruby-like:

1. **Block-based signature definitions** (experimental):
   ```ruby
   signature = DSPy.signature do
     description "Extract entities from text"
     input :text, String
     output :entities, Array[Entity]
   end
   ```

2. **ActiveModel integration** for validations:
   ```ruby
   class UserQuery < DSPy::Signature
     include ActiveModel::Validations
     
     input do
       const :email, String
       validates :email, presence: true, format: /@/
     end
   end
   ```

3. **Middleware stack** for request/response processing:
   ```ruby
   DSPy.config.middleware do |m|
     m.use RateLimiter, requests_per_minute: 60
     m.use ResponseCache, expires_in: 5.minutes
     m.use TokenCounter
   end
   ```

## Try It Yourself

The best way to appreciate DSPy.rb's Ruby-first design is to use it:

```bash
gem install dspy
```

Or in your Gemfile:
```ruby
gem 'dspy', '~> 0.7'
```

We'd love to hear your thoughts on making DSPy.rb even more Ruby-idiomatic. What patterns from your favorite Ruby libraries should we adopt? Let us know in the [GitHub discussions](https://github.com/vicentereig/dspy.rb/discussions).

---

*DSPy.rb is built by Rubyists, for Rubyists. We believe AI development should feel as natural as writing any other Ruby code.*