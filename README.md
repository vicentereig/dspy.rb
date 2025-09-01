# DSPy.rb

[![Gem Version](https://img.shields.io/gem/v/dspy)](https://rubygems.org/gems/dspy)
[![Total Downloads](https://img.shields.io/gem/dt/dspy)](https://rubygems.org/gems/dspy)
[![Build Status](https://img.shields.io/github/actions/workflow/status/vicentereig/dspy.rb/ruby.yml?branch=main&label=build)](https://github.com/vicentereig/dspy.rb/actions/workflows/ruby.yml)
[![Documentation](https://img.shields.io/badge/docs-vicentereig.github.io%2Fdspy.rb-blue)](https://vicentereig.github.io/dspy.rb/)

**Build reliable LLM applications in Ruby using composable, type-safe modules.**

DSPy.rb brings structured LLM programming to Ruby developers. Instead of wrestling with prompt strings and parsing 
responses, you define typed signatures and compose them into pipelines that just work.

Traditional prompting is like writing code with string concatenation: it works until it doesn't. DSPy.rb brings you 
the programming approach pioneered by [dspy.ai](https://dspy.ai/): instead of crafting fragile prompts, you define modular 
signatures and let the framework handle the messy details.

DSPy.rb is an idiomatic Ruby port of Stanford's [DSPy framework](https://github.com/stanfordnlp/dspy). While implementing 
the core concepts of signatures, predictors, and optimization from the original Python library, DSPy.rb embraces Ruby 
conventions and adds Ruby-specific innovations like CodeAct agents and enhanced production instrumentation.

The result? LLM applications that actually scale and don't break when you sneeze.

## Your First DSPy Program

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

## What You Get

**Core Building Blocks:**
- **Signatures** - Define input/output schemas using Sorbet types with T::Enum and union type support
- **Predict** - LLM completion with structured data extraction and multimodal support
- **Chain of Thought** - Step-by-step reasoning for complex problems with automatic prompt optimization
- **ReAct** - Tool-using agents with type-safe tool definitions and error recovery
- **CodeAct** - Dynamic code execution agents for programming tasks
- **Module Composition** - Combine multiple LLM calls into production-ready workflows

**Optimization & Evaluation:**
- **Prompt Objects** - Manipulate prompts as first-class objects instead of strings
- **Typed Examples** - Type-safe training data with automatic validation
- **Evaluation Framework** - Advanced metrics beyond simple accuracy with error-resilient pipelines
- **MIPROv2 Optimization** - Automatic prompt optimization with storage and persistence

**Production Features:**
- **Reliable JSON Extraction** - Native OpenAI structured outputs, Anthropic extraction patterns, and automatic strategy selection with fallback
- **Type-Safe Configuration** - Strategy enums with automatic provider optimization (Strict/Compatible modes)
- **Smart Retry Logic** - Progressive fallback with exponential backoff for handling transient failures
- **Zero-Config Langfuse Integration** - Set env vars and get automatic OpenTelemetry traces in Langfuse
- **Performance Caching** - Schema and capability caching for faster repeated operations
- **File-based Storage** - Optimization result persistence with versioning
- **Structured Logging** - JSON and key=value formats with span tracking

**Developer Experience:**
- LLM provider support using official Ruby clients:
  - [OpenAI Ruby](https://github.com/openai/openai-ruby) with vision model support
  - [Anthropic Ruby SDK](https://github.com/anthropics/anthropic-sdk-ruby) with multimodal capabilities
  - [Ollama](https://ollama.com/) via OpenAI compatibility layer for local models
- **Multimodal Support** - Complete image analysis with DSPy::Image, type-safe bounding boxes, vision-capable models
- Runtime type checking with [Sorbet](https://sorbet.org/) including T::Enum and union types
- Type-safe tool definitions for ReAct agents
- Comprehensive instrumentation and observability

## Development Status

DSPy.rb is actively developed and approaching stability. The core framework is production-ready with 
comprehensive documentation, but I'm battle-testing features through the 0.x series before committing 
to a stable v1.0 API. 

Real-world usage feedback is invaluable - if you encounter issues or have suggestions, please open a GitHub issue!

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
- **[Multimodal Support](docs/src/core-concepts/multimodal.md)** - Image analysis with vision-capable models
- **[Examples & Validation](docs/src/core-concepts/examples.md)** - Type-safe training data

### Optimization
- **[Evaluation Framework](docs/src/optimization/evaluation.md)** - Advanced metrics beyond simple accuracy
- **[Prompt Optimization](docs/src/optimization/prompt-optimization.md)** - Manipulate prompts as objects
- **[MIPROv2 Optimizer](docs/src/optimization/miprov2.md)** - Automatic optimization algorithms

### Production Features
- **[Storage System](docs/src/production/storage.md)** - Persistence and optimization result storage
- **[Observability](docs/src/production/observability.md)** - Zero-config Langfuse integration and structured logging

### Advanced Usage
- **[Complex Types](docs/src/advanced/complex-types.md)** - Sorbet type integration with automatic coercion for structs, enums, and arrays
- **[Manual Pipelines](docs/src/advanced/pipelines.md)** - Manual module composition patterns
- **[RAG Patterns](docs/src/advanced/rag.md)** - Manual RAG implementation with external services
- **[Custom Metrics](docs/src/advanced/custom-metrics.md)** - Proc-based evaluation logic

## Quick Start

### Installation

Add to your Gemfile:

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

## Recent Achievements

DSPy.rb has rapidly evolved from experimental to production-ready:

### Foundation
- ✅ **JSON Parsing Reliability** - Native OpenAI structured outputs, strategy selection, retry logic
- ✅ **Type-Safe Strategy Configuration** - Provider-optimized automatic strategy selection  
- ✅ **Core Module System** - Predict, ChainOfThought, ReAct, CodeAct with type safety
- ✅ **Production Observability** - OpenTelemetry, New Relic, and Langfuse integration
- ✅ **Optimization Framework** - MIPROv2 algorithm with storage & persistence

### Recent Advances  
- ✅ **Comprehensive Multimodal Framework** - Complete image analysis with `DSPy::Image`, type-safe bounding boxes, vision model integration
- ✅ **Advanced Type System** - `T::Enum` integration, union types for agentic workflows, complex type coercion
- ✅ **Production-Ready Evaluation** - Multi-factor metrics beyond accuracy, error-resilient evaluation pipelines
- ✅ **Documentation Ecosystem** - `llms.txt` for AI assistants, ADRs, blog articles, comprehensive examples
- ✅ **API Maturation** - Simplified idiomatic patterns, better error handling, production-proven designs

## Roadmap - Production Battle-Testing Toward v1.0

DSPy.rb has transitioned from **feature building** to **production validation**. The core framework is
feature-complete and stable - now I'm focusing on real-world usage patterns, performance optimization, 
and ecosystem integration.

**Current Focus Areas:**

### Production Readiness
- 🚧 **Production Patterns** - Real-world usage validation and performance optimization
- 🚧 **Ruby Ecosystem Integration** - Rails integration, Sidekiq compatibility, deployment patterns
- 🚧 **Scale Testing** - High-volume usage, memory management, connection pooling
- 🚧 **Error Recovery** - Robust failure handling patterns for production environments

### Ecosystem Expansion  
- 🚧 **Model Context Protocol (MCP)** - Integration with MCP ecosystem
- 🚧 **Additional Provider Support** - Azure OpenAI, local models beyond Ollama
- 🚧 **Tool Ecosystem** - Expanded tool integrations for ReAct agents

### Community & Adoption
- 🚧 **Community Examples** - Real-world applications and case studies
- 🚧 **Contributor Experience** - Making it easier to contribute and extend
- 🚧 **Performance Benchmarks** - Comparative analysis vs other frameworks

**v1.0 Philosophy:** 
v1.0 will be released after extensive production battle-testing, not after checking off features. 
The API is already stable - v1.0 represents confidence in production reliability backed by real-world validation.

## License

This project is licensed under the MIT License.
