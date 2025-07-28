# DSPy.rb

[![Gem Version](https://img.shields.io/gem/v/dspy)](https://rubygems.org/gems/dspy)
[![Total Downloads](https://img.shields.io/gem/dt/dspy)](https://rubygems.org/gems/dspy)

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
- **Reliable JSON Extraction** - Native OpenAI structured outputs, Anthropic extraction patterns, and automatic strategy selection with fallback
- **Type-Safe Configuration** - Strategy enums with automatic provider optimization (Strict/Compatible modes)
- **Smart Retry Logic** - Progressive fallback with exponential backoff for handling transient failures
- **Performance Caching** - Schema and capability caching for faster repeated operations
- **File-based Storage** - Optimization result persistence with versioning
- **Multi-Platform Observability** - OpenTelemetry, New Relic, and Langfuse integration
- **Comprehensive Instrumentation** - Event tracking, performance monitoring, and detailed logging

**Developer Experience:**
- LLM provider support using official Ruby clients:
  - [OpenAI Ruby](https://github.com/openai/openai-ruby)
  - [Anthropic Ruby SDK](https://github.com/anthropics/anthropic-sdk-ruby)
  - [Ollama](https://ollama.com/) via OpenAI compatibility layer
- Runtime type checking with [Sorbet](https://sorbet.org/)
- Type-safe tool definitions for ReAct agents
- Comprehensive instrumentation and observability

## Development Status

DSPy.rb is actively developed and approaching stability at **v0.13.0**. The core framework is production-ready with comprehensive documentation, but I'm battle-testing features through the 0.x series before committing to a stable v1.0 API. 

Real-world usage feedback is invaluable - if you encounter issues or have suggestions, please open a GitHub issue!

## Quick Start

### Installation

```ruby
gem 'dspy', '~> 0.13'
```

Or add to your Gemfile:

```ruby
gem 'dspy'
```

Then run:

```bash
bundle install
```

#### System Dependencies for Ubuntu/Pop!_OS

If you need to compile the `polars-df` dependency from source (used for data processing in evaluations), install these system packages:

```bash
# Update package list
sudo apt-get update

# Install Ruby development files (if not already installed)
sudo apt-get install ruby-full ruby-dev

# Install essential build tools
sudo apt-get install build-essential

# Install Rust and Cargo (required for polars-df compilation)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Install CMake (often needed for Rust projects)
sudo apt-get install cmake
```

**Note**: The `polars-df` gem compilation can take 15-20 minutes. Pre-built binaries are available for most platforms, so compilation is only needed if a pre-built binary isn't available for your system.

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

### LLM-Friendly Documentation

For LLMs and AI assistants working with DSPy.rb:
- **[llms.txt](https://vicentereig.github.io/dspy.rb/llms.txt)** - Concise reference optimized for LLMs
- **[llms-full.txt](https://vicentereig.github.io/dspy.rb/llms-full.txt)** - Comprehensive API documentation

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

## Recent Achievements

DSPy.rb has rapidly evolved from experimental to production-ready:

- ✅ **JSON Parsing Reliability** (v0.8.0) - Native OpenAI structured outputs, strategy selection, retry logic
- ✅ **Type-Safe Strategy Configuration** (v0.9.0) - Provider-optimized automatic strategy selection  
- ✅ **Documentation Website** (v0.6.4) - Comprehensive docs at [vicentereig.github.io/dspy.rb](https://vicentereig.github.io/dspy.rb)
- ✅ **Production Observability** - OpenTelemetry, New Relic, and Langfuse integration
- ✅ **Optimization Framework** - MIPROv2 algorithm with storage & persistence
- ✅ **Core Module System** - Predict, ChainOfThought, ReAct, CodeAct with type safety

## Roadmap - Battle-Testing Toward v1.0

DSPy.rb is currently at **v0.13.0** and approaching stability. I'm focusing on real-world usage and refinement through the 0.14, 0.15+ series before committing to a stable v1.0 API.

**Current Focus Areas:**
- 🚧 **Ollama Support** - Local model integration
- 🚧 **Context Engineering** - Advanced prompt optimization techniques
- 🚧 **MCP Support** - Model Context Protocol integration
- 🚧 **Agentic Memory** - Persistent agent state management
- 🚧 **Performance Optimization** - Based on production usage patterns

**v1.0 Philosophy:** 
v1.0 will be released after extensive production battle-testing, not after checking off features. This ensures a stable, reliable API backed by real-world validation.

## License

This project is licensed under the MIT License.
