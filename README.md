# DSPy.rb

**Build reliable LLM applications in Ruby using composable, type-safe modules.**

DSPy.rb brings structured LLM programming to Ruby developers.
Instead of wrestling with prompt strings and parsing responses,
you define typed signatures and compose them into pipelines that just work.

Traditional prompting is like writing code with string concatenation: it works until 
it doesn't. DSPy.rb brings you the programming approach pioneered 
by [dspy.ai](https://dspy.ai/): instead of crafting fragile prompts, you define 
modular signatures and let the framework handle the messy details.

The result? LLM applications that actually scale and don't break when you sneeze.

## What You Get

**Core Building Blocks:**
- **Signatures** - Define input/output schemas using Sorbet types
- **Predict** - Basic LLM completion with structured data
- **Chain of Thought** - Step-by-step reasoning for complex problems
- **ReAct** - Tool-using agents that can actually get things done
- **RAG** - Context-enriched responses from your data
- **Multi-stage Pipelines** - Compose multiple LLM calls into workflows
- OpenAI and Anthropic support via [Ruby LLM](https://github.com/crmne/ruby_llm)
- Runtime type checking with [Sorbet](https://sorbet.org/)
- Type-safe tool definitions for ReAct agents

## Fair Warning

This is fresh off the oven and evolving fast. 
I'm actively building this as a Ruby port of the [DSPy library](https://dspy.ai/). 
If you hit bugs or want to contribute, just email me directly!

## What's Next
These are my goals to release v1.0.

- Solidify prompt optimization
- OTel Integration
- Ollama support

## Installation

Skip the gem for now - install straight from this repo while I prep the first release:
```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

## Usage Examples

### Simple Prediction

```ruby
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
result = classify.call(sentence: "This book was super fun to read, though not the last chapter.")

# result is a properly typed T::Struct instance
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

### ReAct Agents with Tools

```ruby

class DeepQA < DSPy::Signature
  description "Answer questions with consideration for the context"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

# Define tools for the agent
class CalculatorTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'calculator'
  tool_description 'Performs basic arithmetic operations'

  sig { params(operation: String, num1: Float, num2: Float).returns(T.any(Float, String)) }
  def call(operation:, num1:, num2:)
    case operation.downcase
    when 'add' then num1 + num2
    when 'subtract' then num1 - num2
    when 'multiply' then num1 * num2
    when 'divide'
      return "Error: Cannot divide by zero" if num2 == 0
      num1 / num2
    else
      "Error: Unknown operation '#{operation}'. Use add, subtract, multiply, or divide"
    end
  end

# Create ReAct agent with tools
agent = DSPy::ReAct.new(DeepQA, tools: [CalculatorTool.new])

# Run the agent
result = agent.forward(question: "What is 42 plus 58?")
puts result.answer # => "100"
puts result.history # => Array of reasoning steps and tool calls
```

### Multi-stage Pipelines
Outline the sections of an article and draft them out.

```ruby

# write an article!
drafter = ArticleDrafter.new
article = drafter.forward(topic: "The impact of AI on software development") # { title: '....', sections: [{content: '....'}]}

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

```

## Working with Complex Types

### Enums

```ruby
class Color < T::Enum
  enums do
    Red = new
    Green = new
    Blue = new
  end
end

class ColorSignature < DSPy::Signature
  description "Identify the dominant color in a description"

  input do
    const :description, String,
      description: 'Description of an object or scene'
  end

  output do
    const :color, Color,
      description: 'The dominant color (Red, Green, or Blue)'
  end
end

predictor = DSPy::Predict.new(ColorSignature)
result = predictor.call(description: "A red apple on a wooden table")
puts result.color  # => #<Color::Red>
```

### Optional Fields and Defaults

```ruby
class AnalysisSignature < DSPy::Signature
  description "Analyze text with optional metadata"

  input do
    const :text, String,
      description: 'Text to analyze'
    const :include_metadata, T::Boolean,
      description: 'Whether to include metadata in analysis',
      default: false
  end

  output do
    const :summary, String,
      description: 'Summary of the text'
    const :word_count, Integer,
      description: 'Number of words (optional)',
      default: 0
  end
end
```

## Advanced Usage Patterns

### Multi-stage Pipelines

```ruby
class TopicSignature < DSPy::Signature
  description "Extract main topic from text"
  
  input do
    const :content, String,
      description: 'Text content to analyze'
  end
  
  output do
    const :topic, String,
      description: 'Main topic of the content'
  end
end

class SummarySignature < DSPy::Signature
  description "Create summary focusing on specific topic"
  
  input do
    const :content, String,
      description: 'Original text content'
    const :topic, String,
      description: 'Topic to focus on'
  end
  
  output do
    const :summary, String,
      description: 'Topic-focused summary'
  end
end

class ArticlePipeline < DSPy::Signature
  extend T::Sig
  
  def initialize
    @topic_extractor = DSPy::Predict.new(TopicSignature)
    @summarizer = DSPy::ChainOfThought.new(SummarySignature)
  end
  
  sig { params(content: String).returns(T.untyped) }
  def forward(content:)
    # Extract topic
    topic_result = @topic_extractor.call(content: content)
    
    # Create focused summary
    summary_result = @summarizer.call(
      content: content,
      topic: topic_result.topic
    )
    
    {
      topic: topic_result.topic,
      summary: summary_result.summary,
      reasoning: summary_result.reasoning
    }
  end
end

# Usage
pipeline = ArticlePipeline.new
result = pipeline.call(content: "Long article content...")
```

### Retrieval Augmented Generation

```ruby
class ContextualQA < DSPy::Signature
  description "Answer questions using relevant context"
  
  input do
    const :question, String,
      description: 'The question to answer'
    const :context, T::Array[String],
      description: 'Relevant context passages'
  end

  output do
    const :answer, String,
      description: 'Answer based on the provided context'
    const :confidence, Float,
      description: 'Confidence in the answer (0.0 to 1.0)'
  end
end

# Usage with retriever
retriever = YourRetrieverClass.new
qa = DSPy::ChainOfThought.new(ContextualQA)

question = "What is the capital of France?"
context = retriever.retrieve(question)  # Returns array of strings

result = qa.call(question: question, context: context)
puts result.reasoning   # Step-by-step reasoning
puts result.answer      # "Paris"
puts result.confidence  # 0.95
```

## License

This project is licensed under the MIT License.
