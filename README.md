# DSPy.rb

**Build reliable LLM applications in Ruby using composable, type-safe modules.**

DSPy.rb brings structured LLM programming to Ruby developers. Instead of wrestling with prompt strings and parsing responses, you define typed signatures and compose them into pipelines that just work.

Traditional prompting is like writing code with string concatenation: it works until it doesn't. DSPy.rb brings you the programming approach pioneered by [dspy.ai](https://dspy.ai/): instead of crafting fragile prompts, you define modular signatures and let the framework handle the messy details.

The result? LLM applications that actually scale and don't break when you sneeze.

## What You Get

**Core Building Blocks:**
- **Signatures** - Define input/output schemas using Sorbet types
- **Predict** - Basic LLM completion with structured data
- **Chain of Thought** - Step-by-step reasoning for complex problems
- **ReAct** - Tool-using agents that can actually get things done
- **RAG** - Context-enriched responses from your data
- **Multi-stage Pipelines** - Compose multiple LLM calls into workflows

**Optimization & Evaluation:**
- **Prompt Objects** - Manipulate prompts as first-class objects instead of strings
- **Typed Examples** - Type-safe training data with automatic validation
- **Evaluation Framework** - Systematic testing with built-in metrics
- **MIPROv2 Optimizer** - State-of-the-art automatic prompt optimization
- **Simple Optimizer** - Random/grid search for quick experimentation

**Production Features:**
- **Storage System** - Persistent optimization result storage with search and filtering
- **Registry System** - Version control for optimized signatures with deployment tracking
- **Multi-Platform Observability** - OpenTelemetry, New Relic, and Langfuse integration
- **Auto-deployment** - Intelligent deployment based on performance improvements
- **Rollback Protection** - Automatic rollback on performance degradation

**Developer Experience:**
- LLM provider support using official Ruby clients:
  - [OpenAI Ruby](https://github.com/openai/openai-ruby)
  - [Anthropic Ruby SDK](https://github.com/anthropics/anthropic-sdk-ruby)
- Runtime type checking with [Sorbet](https://sorbet.org/)
- Type-safe tool definitions for ReAct agents
- Comprehensive instrumentation and observability

## Fair Warning

This is fresh off the oven and evolving fast. I'm actively building this as a Ruby port of the [DSPy library](https://dspy.ai/). If you hit bugs or want to contribute, just email me directly!

## Quick Start

### Installation

Skip the gem for now - install straight from this repo while I prep the first release:

```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

### Your First DSPy Program

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
result = classify.call(sentence: "This book was super fun to read!")

puts result.sentiment    # => #<Sentiment::Positive>  
puts result.confidence   # => 0.85
```

## Documentation

### Getting Started
- **[Installation & Setup](docs/getting-started/installation.md)** - Detailed installation and configuration
- **[Quick Start Guide](docs/getting-started/quick-start.md)** - Your first DSPy programs
- **[Core Concepts](docs/getting-started/core-concepts.md)** - Understanding signatures, predictors, and modules

### Core Features
- **[Signatures & Types](docs/core-concepts/signatures.md)** - Define typed interfaces for LLM operations
- **[Predictors](docs/core-concepts/predictors.md)** - Predict, ChainOfThought, ReAct, and more
- **[Modules & Pipelines](docs/core-concepts/modules.md)** - Compose complex multi-stage workflows
- **[Examples & Validation](docs/core-concepts/examples.md)** - Type-safe training data

### Optimization
- **[Evaluation Framework](docs/optimization/evaluation.md)** - Systematic testing with metrics
- **[Prompt Optimization](docs/optimization/prompt-optimization.md)** - Manipulate prompts as objects
- **[MIPROv2 Optimizer](docs/optimization/miprov2.md)** - State-of-the-art automatic optimization
- **[Simple Optimizer](docs/optimization/simple-optimizer.md)** - Quick experimentation with random/grid search

### Production Features
- **[Storage System](docs/production/storage.md)** - Persist and search optimization results
- **[Registry & Versions](docs/production/registry.md)** - Version control with deployment tracking
- **[Observability](docs/production/observability.md)** - Multi-platform monitoring and metrics

### Advanced Usage
- **[Complex Types](docs/advanced/complex-types.md)** - Enums, optional fields, and defaults
- **[Multi-stage Pipelines](docs/advanced/pipelines.md)** - Advanced composition patterns
- **[RAG Implementation](docs/advanced/rag.md)** - Retrieval Augmented Generation
- **[Custom Metrics](docs/advanced/custom-metrics.md)** - Domain-specific evaluation logic

## What's Next

These are my goals to release v1.0.

- ✅ Prompt objects foundation - *Done*
- ✅ Evaluation framework - *Done*  
- ✅ Teleprompter base classes - *Done*
- ✅ MIPROv2 optimization algorithm - *Done*
- ✅ Storage & persistence system - *Done*
- ✅ Registry & version management - *Done*
- ✅ OpenTelemetry integration - *Done*
- ✅ New Relic integration - *Done*
- ✅ Langfuse integration - *Done*
- 🚧 Ollama support
- Context Engineering (see recent research: [How Contexts Fail](https://www.dbreunig.com/2025/06/22/how-contexts-fail-and-how-to-fix-them.html), [How to Fix Your Context](https://www.dbreunig.com/2025/06/26/how-to-fix-your-context.html), [Context Engineering](https://simonwillison.net/2025/Jun/27/context-engineering/))
- Agentic Memory support
- MCP Support
- Documentation website
- Performance benchmarks

## License

This project is licensed under the MIT License.
