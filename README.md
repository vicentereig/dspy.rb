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
- **ReAct** - Tool-using agents with basic tool integration
- **CodeAct** - Dynamic code execution agents for programming tasks
- **Manual Composition** - Combine multiple LLM calls into workflows

**Optimization & Evaluation:**
- **Prompt Objects** - Manipulate prompts as first-class objects instead of strings
- **Typed Examples** - Type-safe training data with automatic validation
- **Evaluation Framework** - Basic testing with simple metrics
- **Basic Optimization** - Simple prompt optimization techniques

**Production Features:**
- **Reliable JSON Extraction** - Automatic strategy selection for OpenAI structured outputs, Anthropic patterns, and fallback modes
- **Smart Retry Logic** - Progressive fallback with exponential backoff for handling transient failures
- **Performance Caching** - Schema and capability caching for faster repeated operations
- **File-based Storage** - Basic optimization result persistence
- **Multi-Platform Observability** - OpenTelemetry, New Relic, and Langfuse integration
- **Basic Instrumentation** - Event tracking and logging

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
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', 
                      api_key: ENV['OPENAI_API_KEY'],
                      structured_outputs: true)  # Enable OpenAI's native JSON mode
end

# Create the predictor and run inference
classify = DSPy::Predict.new(Classify)
result = classify.call(sentence: "This book was super fun to read!")

puts result.sentiment    # => #<Sentiment::Positive>  
puts result.confidence   # => 0.85
```

## Documentation

📖 **[Complete Documentation Website](https://vicentereig.github.io/dspy.rb/)**

### Getting Started
- **[Installation & Setup](docs/src/getting-started/installation.md)** - Detailed installation and configuration
- **[Quick Start Guide](docs/src/getting-started/quick-start.md)** - Your first DSPy programs
- **[Core Concepts](docs/src/getting-started/core-concepts.md)** - Understanding signatures, predictors, and modules

### Core Features
- **[Signatures & Types](docs/src/core-concepts/signatures.md)** - Define typed interfaces for LLM operations
- **[Predictors](docs/src/core-concepts/predictors.md)** - Predict, ChainOfThought, ReAct, and more
- **[Modules & Pipelines](docs/src/core-concepts/modules.md)** - Compose complex multi-stage workflows
- **[Examples & Validation](docs/src/core-concepts/examples.md)** - Type-safe training data

### Optimization
- **[Evaluation Framework](docs/src/optimization/evaluation.md)** - Basic testing with simple metrics
- **[Prompt Optimization](docs/src/optimization/prompt-optimization.md)** - Manipulate prompts as objects
- **[MIPROv2 Optimizer](docs/src/optimization/miprov2.md)** - Basic automatic optimization

### Production Features
- **[Storage System](docs/src/production/storage.md)** - Basic file-based persistence
- **[Observability](docs/src/production/observability.md)** - Multi-platform monitoring and metrics

### Advanced Usage
- **[Complex Types](docs/src/advanced/complex-types.md)** - Sorbet type integration with automatic coercion for structs, enums, and arrays
- **[Manual Pipelines](docs/src/advanced/pipelines.md)** - Manual module composition patterns
- **[RAG Patterns](docs/src/advanced/rag.md)** - Manual RAG implementation with external services
- **[Custom Metrics](docs/src/advanced/custom-metrics.md)** - Proc-based evaluation logic

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
