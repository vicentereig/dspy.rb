# Quick Start Guide

Get up and running with DSPy.rb in minutes.

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
        title: outline.title,
        section: section
      )
    end

    {
      title: outline.title,
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

- Learn about [Core Concepts](core-concepts.md)
- Explore [Signatures & Types](../core-concepts/signatures.md)
- Try [Prompt Optimization](../optimization/prompt-optimization.md)
- Set up [Observability](../enterprise/observability.md)