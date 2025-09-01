---
layout: docs
name: Quick Start
description: Build your first DSPy.rb application in 5 minutes
breadcrumb:
- name: Getting Started
  url: "/getting-started/"
- name: Quick Start
  url: "/getting-started/quick-start/"
prev:
  name: Installation
  url: "/getting-started/installation/"
next:
  name: Core Concepts
  url: "/getting-started/core-concepts/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-08 00:00:00 +0000
---
# Quick Start Guide

Get up and running with DSPy.rb in minutes. This guide shows Ruby-idiomatic patterns for building AI applications.

## Your First DSPy Program

### Basic Prediction

```ruby
require 'dspy'

# Define a signature for sentiment classification
class Classify < DSPy::Signature
  description "Classify sentiment of a given sentence."

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :sentence, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

# Configure DSPy with your LLM
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  # or use Ollama for local models
  # c.lm = DSPy::LM.new('ollama/llama3.2')
end

# Create the predictor and run inference
classify = DSPy::Predict.new(Classify)
result = classify.call(sentence: "This book was super fun to read!")

puts result.sentiment    # => #<Sentiment::Positive>  
puts result.confidence   # => 0.85
```

### Chain of Thought Reasoning

```ruby
class AnswerPredictor < DSPy::Signature
  description "Provides a concise answer to the question"

  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

# Chain of thought automatically adds a 'reasoning' field to the output
qa_cot = DSPy::ChainOfThought.new(AnswerPredictor)
result = qa_cot.call(question: "Two dice are tossed. What is the probability that the sum equals two?")

puts result.reasoning  # => "There is only one way to get a sum of 2..."
puts result.answer     # => "1/36"
```

### Multi-stage Pipelines

```ruby
class Outline < DSPy::Signature
  description "Outline a thorough overview of a topic."

  input do
    const :topic, String
  end

  output do
    const :title, String
    const :sections, T::Array[String]
  end
end

class DraftSection < DSPy::Signature
  description "Draft a section of an article"

  input do
    const :topic, String
    const :title, String
    const :section, String
  end

  output do
    const :content, String
  end
end

class ArticleDrafter < DSPy::Module
  def initialize
    @build_outline = DSPy::ChainOfThought.new(Outline)
    @draft_section = DSPy::ChainOfThought.new(DraftSection)
  end

  def forward(topic:)
    outline = @build_outline.call(topic: topic)
    
    sections = outline.sections.map do |section|
      @draft_section.call(
        topic: topic,
        name: outline.title,
        section: section
      )
    end

    {
      name: outline.title,
      sections: sections.map(&:content)
    }
  end
end

# Use the pipeline
drafter = ArticleDrafter.new
article = drafter.forward(topic: "The impact of AI on software development")
puts article[:title]
puts article[:sections].first
```

## Ruby-Idiomatic Examples

### Working with Collections

DSPy.rb works naturally with Ruby's Enumerable patterns:

```ruby
# Process multiple items with Ruby's collection methods
class BatchProcessor < DSPy::Module
  def initialize
    @classifier = DSPy::Predict.new(Classify)
  end
  
  def process_batch(sentences)
    sentences.map { |sentence| @classifier.call(sentence: sentence) }
             .select { |result| result.confidence > 0.8 }
             .group_by(&:sentiment)
  end
end

# Usage
processor = BatchProcessor.new
results = processor.process_batch([
  "I love this product!",
  "This is terrible.",
  "It's okay, I guess."
])

results[:positive]&.each { |r| puts r.sentence }
```

### Block-Based Configuration

Configure DSPy components with Ruby blocks:

```ruby
# Configure with blocks for cleaner syntax
DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini') do |lm|
    lm.api_key = ENV.fetch('OPENAI_API_KEY')
    lm.temperature = 0.7
    lm.max_tokens = 1000
  end
  
  # Configure logging for observability
  config.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(stream: Rails.root.join('log', 'dspy.log'))
  end
end
```

### Duck Typing with Tools

Create tools that follow Ruby's duck typing principles:

```ruby
# Any object that responds to #call can be a tool
class WeatherTool
  def call(location:)
    # In real app, this would call an API
    { temperature: 72, conditions: "sunny" }
  end
end

# Lambda tools for simple operations
calculator = ->(expression:) { eval(expression) }

# Use with ReAct agent
agent = DSPy::ReAct.new(
  WeatherReport,
  tools: {
    weather: WeatherTool.new,
    calculate: calculator
  }
)
```

## Key Concepts

### Signatures

Signatures define the interface for LLM operations:

```ruby
class YourSignature < DSPy::Signature
  description "Clear description of what this does"
  
  input do
    const :input_field, String, description: "What this field represents"
  end
  
  output do
    const :output_field, String, description: "What the output should be"
  end
end
```

### Predictors

Predictors execute signatures:

- `DSPy::Predict` - Basic LLM completion
- `DSPy::ChainOfThought` - Step-by-step reasoning
- `DSPy::ReAct` - Tool-using agents
- `DSPy::CodeAct` - Dynamic code execution agents

### Modules

Modules compose multiple predictors into pipelines:

```ruby
class YourModule < DSPy::Module
  def initialize
    @predictor1 = DSPy::Predict.new(Signature1)
    @predictor2 = DSPy::ChainOfThought.new(Signature2)
  end
  
  def forward(**inputs)
    result1 = @predictor1.call(**inputs)
    result2 = @predictor2.call(input: result1.output)
    
    { final_result: result2.output }
  end
end
```

## Next Steps

- Learn about [Core Concepts](../core-concepts)
- Explore [Signatures & Types](../../core-concepts/signatures)
- Try [Prompt Optimization](../../optimization/prompt-optimization)
- Set up [Observability](../../production/observability)
