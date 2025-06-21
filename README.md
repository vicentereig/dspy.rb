# DSPy.rb

A Ruby port of the [DSPy library](https://dspy.ai/), enabling a composable and pipeline-oriented approach to programming with Large Language Models (LLMs) in Ruby.

## Contributing

This library is early stage and evolving rapidly. I welcome contributions,
bug reports, and feature requests. Best way to reach out to me is via email.

## Current State

DSPy.rb provides a foundation for composable LLM programming with the following implemented features:

- **Signatures**: Define input/output schemas for LLM interactions using Sorbet types and JSON schemas
- **Predict**: Basic LLM completion with structured inputs and outputs
- **Chain of Thought**: Enhanced reasoning through step-by-step thinking
- **ReAct**: Compose multiple LLM calls in a structured workflow using tools.
- **RAG (Retrieval-Augmented Generation)**: Enriched responses with context from retrieval
- **Multi-stage Pipelines**: Compose multiple LLM calls in a structured workflow

The library currently supports:
- OpenAI and Anthropic via [Ruby LLM](https://github.com/crmne/ruby_llm)
- Runtime type checking with [Sorbet](https://sorbet.org/)
- Enhanced IDE support and autocomplete
- Type-safe tool definitions for ReAct agents

## Installation

This is not even fresh off the oven. I recommend you installing 
it straight from this repo, while I build the first release.

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
```

### RAG (Retrieval-Augmented Generation)
Augment your predictions with additional context.

```ruby
class ContextualQA < DSPy::Signature
  description "Answers the question taking relevant context into account"

  input do
    const :context, T::Array[String]
    const :question, String
  end

  output do
    const :response, String
  end
end

# Use with ColBERTv2 for retrieval (example)
rag = DSPy::ChainOfThought.new(ContextualQA)

context = [
  "DSPy is a framework for programming with language models.",
  "It provides composable modules for LLM interactions.",
  "The framework supports multiple reasoning patterns."
]

result = rag.call(
  context: context,
  question: "What is DSPy?"
)

puts result.response  # => Contextually informed answer
```

## License

This project is licensed under the MIT License.
