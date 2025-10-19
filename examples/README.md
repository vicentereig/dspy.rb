# DSPy.rb Examples

This directory contains practical examples for using DSPy.rb features.

## Setup

Create a `.env` file in the project root with your API keys:
```bash
OPENAI_API_KEY=your-openai-key
ANTHROPIC_API_KEY=your-anthropic-key
```

## Examples by Category

### Optimization

#### `ade_optimizer_miprov2/`

End-to-end optimization workflow using MIPROv2:

- **`main.rb`** - ADE (Automatic Data Evaluation) optimizer walkthrough
- **`data/`** - Sample datasets for optimization trials
- **`results/`** - Saved optimization outputs and metrics

#### `ade_optimizer_gepa/`

Reflective optimization of the same ADE task using GEPA with per-predictor feedback:

- **`main.rb`** - GEPA optimizer walkthrough
- **`data/`** - Shared dataset cache directory
- **`results/`** - Saved GEPA optimization outputs and metrics

### Multimodal (`multimodal/`)

Examples for working with images and vision models:

- **`image_analysis.rb`** - Analyze images for objects, colors, and mood
- **`bounding_box_detection.rb`** - Detect objects and return coordinates

### Agent Examples (`coffee-shop-agent/`)

- **`coffee_shop_agent.rb`** - Interactive coffee ordering chatbot with memory

### Evaluation (`sentiment-evaluation/`)

- **`sentiment_classifier.rb`** - Tweet sentiment classification with evaluation

## Quick Start

1. **Basic prediction:**
```ruby
require 'dspy'

class QASignature < DSPy::Signature
  description "Answer questions concisely"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini')
end

predictor = DSPy::Predict.new(QASignature)
result = predictor.call(question: "What is 2+2?")
puts result.answer
```

2. **Chain of thought reasoning:**
```ruby
cot = DSPy::ChainOfThought.new(QASignature)
result = cot.call(question: "Explain why 2+2=4")
puts result.reasoning  # Shows step-by-step thinking
puts result.answer     # Shows final answer
```

3. **Creating training examples:**
```ruby
examples = [
  DSPy::Example.new(
    signature_class: QASignature,
    input: { question: "What is the capital of France?" },
    expected: { answer: "Paris" }
  )
]
```

## Running Examples

All examples check for required API keys and will exit with a helpful message if missing.

```bash
# Run a specific example
bundle exec ruby examples/sentiment-evaluation/sentiment_classifier.rb

# Run with debug output
DEBUG=true bundle exec ruby examples/sentiment-evaluation/sentiment_classifier.rb
```

## Tips

- Start with simple examples before trying optimization
- Use `DSPy::ChainOfThought` for complex reasoning tasks
- Check example outputs for expected data structures
- Examples use realistic datasets and evaluation metrics
