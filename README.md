# DSPy.rb

A Ruby port of the [DSPy library](https://dspy.ai/), enabling a composable and pipeline-oriented approach to programming with Large Language Models (LLMs) in Ruby.

## Current State

DSPy.rb provides a foundation for composable LLM programming with the following implemented features:

- **Signatures**: Define input/output schemas for LLM interactions using JSON schemas
- **Predict**: Basic LLM completion with structured inputs and outputs
- **Chain of Thought**: Enhanced reasoning through step-by-step thinking
- **RAG (Retrieval-Augmented Generation)**: Enriched responses with context from retrieval
- **Multi-stage Pipelines**: Compose multiple LLM calls in a structured workflow

The library currently supports:
- OpenAI and Anthropic via [Ruby LLM](https://github.com/crmne/ruby_llm)
- JSON schema validation with [dry-schema](https://dry-rb.org/gems/dry-schema/)

## Installation

This is not even fresh  off the oven. I recommend you installing 
it straight from this repo, while I build the first release.

```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

## Usage Examples

### Basic Prediction

```ruby
# Define a signature for sentiment classification
class Classify < DSPy::Signature
  description "Classify sentiment of a given sentence."

  input do
    required(:sentence).value(:string).meta(description: 'The sentence to analyze')
  end

  output do
    required(:sentiment).value(included_in?: %w(positive negative neutral))
      .meta(description: 'The sentiment classification')
    required(:confidence).value(:float).meta(description: 'Confidence score')
  end
end

# Initialize the language model
lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
DSPy.configure(lm: lm)

# Create the predictor and run inference
classify = DSPy::Predict.new(Classify)
result = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
# => {:confidence=>0.85, :sentence=>"This book was super fun to read, though not the last chapter.", :sentiment=>"positive"}
```

### Chain of Thought Reasoning

```ruby
class AnswerPredictor < DSPy::Signature
  description "Provides a concise answer to the question"

  input do
    required(:question).value(:string)
  end
  
  output do
    required(:answer).value(:string)
  end
end

qa_cot = DSPy::ChainOfThought.new(AnswerPredictor)
response = qa_cot.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
# Result includes reasoning and answer in the response
# {:question=>"...", :answer=>"1/36", :reasoning=>"There is only one way to get a sum of 2..."}
```

### RAG (Retrieval-Augmented Generation)

```ruby
class ContextualQA < DSPy::Signature
  description "Answers questions using relevant context"
  
  input do
    required(:context).value(Types::Array.of(:string))
    required(:question).filled(:string)
  end

  output do
    required(:response).filled(:string)
  end
end

# Set up retriever (example using ColBERT)
retriever = ColBERTv2.new(url: 'http://your-retriever-endpoint')
results = retriever.call('your query').map(&:long_text)

# Generate a contextual response
rag = DSPy::ChainOfThought.new(ContextualQA)
prediction = rag.call(question: question, context: results)
```

### Multi-stage Pipeline

```ruby
# Create a pipeline for article drafting
class ArticleDrafter < DSPy::Module
  def initialize
    @build_outline = DSPy::ChainOfThought.new(Outline)
    @draft_section = DSPy::ChainOfThought.new(DraftSection)
  end

  def forward(topic)
    # First build the outline
    outline = @build_outline.call(topic: topic)
    
    # Then draft each section
    sections = []
    (outline[:section_subheadings] || {}).each do |heading, subheadings|
      section = @draft_section.call(
        topic: outline[:title],
        section_heading: "## #{heading}",
        section_subheadings: [subheadings].flatten.map { |sh| "### #{sh}" }
      )
      sections << section
    end

    DraftArticle.new(title: outline[:title], sections: sections)
  end
end

# Usage
drafter = ArticleDrafter.new
article = drafter.call("World Cup 2002")
```

## Roadmap

### First Release
- [x] Signatures and Predict module
- [x] RAG examples
- [x] Multi-Stage Pipelines
- [x] Validate inputs and outputs with JSON Schema
- [ ] Convert responses from hashes to Dry Poros (currently tons of footguns with hashes :fire:)
- [ ] Implement ReAct module for reasoning and acting
- [ ] Add OpenTelemetry instrumentation
- [ ] Improve logging
- [ ] Add streaming support
- [ ] Ensure thread safety
- [ ] Comprehensive initial documentation

### Upcoming Features

- [ ] Support for multiple LM providers (Anthropic, etc.)
- [ ] Support for reasoning providers
- [ ] Adaptive Graph of Thoughts with Tools

### Optimizers

- [ ] Optimizing prompts: RAG
- [ ] Optimizing prompts: Chain of Thought
- [ ] Optimizing prompts: ReAct
- [ ] Optimizing weights: Classification

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE.txt file for details.
