# DSPy.rb

[![Gem Version](https://img.shields.io/gem/v/dspy)](https://rubygems.org/gems/dspy)
[![Total Downloads](https://img.shields.io/gem/dt/dspy)](https://rubygems.org/gems/dspy)
[![Build Status](https://img.shields.io/github/actions/workflow/status/vicentereig/dspy.rb/ruby.yml?branch=main&label=build)](https://github.com/vicentereig/dspy.rb/actions/workflows/ruby.yml)
[![Documentation](https://img.shields.io/badge/docs-vicentereig.github.io%2Fdspy.rb-blue)](https://vicentereig.github.io/dspy.rb/)

> [!NOTE]
> The core Prompt Engineering Framework is production-ready with
> comprehensive documentation. I am focusing now on educational content on systematic Prompt Optimization and Context Engineering.
> Your feedback is invaluable. if you encounter issues, please open an [issue](https://github.com/vicentereig/dspy.rb/issues). If you have suggestions, open a [new thread](https://github.com/vicentereig/dspy.rb/discussions).  
> 
> If you want to contribute, feel free to reach out to me to coordinate efforts: hey at vicente.services
>
> And, yes, this is 100% a legit project. :) 


**Build reliable LLM applications in idiomatic Ruby using composable, type-safe modules.**

The Ruby framework for programming with large language models. DSPy.rb brings structured LLM programming to Ruby developers, programmatic Prompt Engineering and Context Engineering. 
Instead of wrestling with prompt strings and parsing responses, you define typed signatures using idiomatic Ruby to compose and decompose AI Worklows and AI Agents.

**Prompts are the just Functions.** Traditional prompting is like writing code with string concatenation: it works until it doesn't. DSPy.rb brings you 
the programming approach pioneered by [dspy.ai](https://dspy.ai/): instead of crafting fragile prompts, you define modular 
signatures and let the framework handle the messy details.

DSPy.rb is an idiomatic Ruby surgical port of Stanford's [DSPy framework](https://github.com/stanfordnlp/dspy). While implementing 
the core concepts of signatures, predictors, and the main optimization algorithms from the original Python library, DSPy.rb embraces Ruby 
conventions and adds Ruby-specific innovations like Sorbet-base Typed system, ReAct loops, and production-ready integrations like non-blocking Open Telemetry Instrumentation.

**What you get?** Ruby LLM applications that actually scale and don't break when you sneeze.

Check the [examples](examples/) and take them for a spin!

## Your First DSPy Program
### Installation

Add to your Gemfile:

```ruby
gem 'dspy'
```

and

```bash
bundle install
```

### Optional Sibling Gems

DSPy.rb ships multiple gems from this monorepo so you only install what you need. Add these alongside `dspy`:

| Gem | Description |
| --- | --- |
| `dspy-schema` | Exposes `DSPy::TypeSystem::SorbetJsonSchema` so other projects (e.g., exa-ruby) can convert Sorbet types to JSON Schema without pulling the full DSPy stack. |
| `dspy-code_act` | Think-Code-Observe agents that can synthesize and execute Ruby code safely. |
| `dspy-datasets` | Dataset helpers plus Parquet/Polars tooling for richer evaluation corpora. |
| `dspy-evals` | High-throughput evaluation harness with metrics, callbacks, and regression fixtures. |
| `dspy-miprov2` | Bayesian optimization + Gaussian Process backend for the MIPROv2 teleprompter. |
| `dspy-gepa` | `DSPy::Teleprompt::GEPA`, reflection loops, experiment tracking, and telemetry adapters built on top of the GEPA core gem. |
| `gepa` | GEPA optimizer core (Pareto engine, telemetry, reflective proposer) shared by `dspy-gepa`. |
| `dspy-o11y` | Core observability APIs: `DSPy::Observability`, async span processor, and observation type helpers. |
| `dspy-o11y-langfuse` | Auto-configures DSPy observability to stream spans to Langfuse via OpenTelemetry. |

Set the matching `DSPY_WITH_*` environment variables (see `Gemfile`) to include or exclude each sibling gem when running Bundler locally (for example `DSPY_WITH_GEPA=1` or `DSPY_WITH_O11Y_LANGFUSE=1`).
### Your First Reliable Predictor

```ruby

# Configure DSPy globablly to use your fave LLM - you can override this on an instance levle. 
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini',
                      api_key: ENV['OPENAI_API_KEY'],
                      structured_outputs: true)  # Enable OpenAI's native JSON mode
end

# Define a signature for sentiment classification - instead of writing a full prompt!
class Classify < DSPy::Signature
  description "Classify sentiment of a given sentence." # sets the goal of the underlying prompt

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end
  
  # Structured Inputs: makes sure you are sending only valid prompt inputs to your model
  input do
    const :sentence, String, description: 'The sentence to analyze'
  end

  # Structured Outputs: your predictor will validate the output of the model too.
  output do
    const :sentiment, Sentiment, description: 'The sentiment of the sentence'
    const :confidence, Float, description: 'A number between 0.0 and 1.0'
  end
end

# Wire it to the simplest prompting technique - a Predictn.
classify = DSPy::Predict.new(Classify)
# it may raise an error if you mess the inputs or your LLM messes the outputs.
result = classify.call(sentence: "This book was super fun to read!")

puts result.sentiment    # => #<Sentiment::Positive>  
puts result.confidence   # => 0.85
```

### Access to 200+ Models Across 5 Providers

DSPy.rb provides unified access to major LLM providers with provider-specific optimizations:

```ruby
# OpenAI (GPT-4, GPT-4o, GPT-4o-mini, GPT-5, etc.)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini',
                      api_key: ENV['OPENAI_API_KEY'],
                      structured_outputs: true)  # Native JSON mode
end

# Google Gemini (Gemini 1.5 Pro, Flash, Gemini 2.0, etc.)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('gemini/gemini-2.5-flash',
                      api_key: ENV['GEMINI_API_KEY'],
                      structured_outputs: true)  # Native structured outputs
end

# Anthropic Claude (Claude 3.5, Claude 4, etc.)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('anthropic/claude-sonnet-4-5-20250929',
                      api_key: ENV['ANTHROPIC_API_KEY'],
                      structured_outputs: true)  # Tool-based extraction (default)
end

# Ollama - Run any local model (Llama, Mistral, Gemma, etc.)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('ollama/llama3.2')  # Free, runs locally, no API key needed
end

# OpenRouter - Access to 200+ models from multiple providers
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free',
                      api_key: ENV['OPENROUTER_API_KEY'])
end
```

## What You Get

**Developer Experience:**
- LLM provider support using official Ruby clients:
  - [OpenAI Ruby](https://github.com/openai/openai-ruby) with vision model support
  - [Anthropic Ruby SDK](https://github.com/anthropics/anthropic-sdk-ruby) with multimodal capabilities
  - [Google Gemini API](https://ai.google.dev/) with native structured outputs
  - [Ollama](https://ollama.com/) via OpenAI compatibility layer for local models
- **Multimodal Support** - Complete image analysis with DSPy::Image, type-safe bounding boxes, vision-capable models
- Runtime type checking with [Sorbet](https://sorbet.org/) including T::Enum and union types
- Type-safe tool definitions for ReAct agents
- Comprehensive instrumentation and observability

**Core Building Blocks:**
- **Signatures** - Define input/output schemas using Sorbet types with T::Enum and union type support
- **Predict** - LLM completion with structured data extraction and multimodal support
- **Chain of Thought** - Step-by-step reasoning for complex problems with automatic prompt optimization
- **ReAct** - Tool-using agents with type-safe tool definitions and error recovery
- **Module Composition** - Combine multiple LLM calls into production-ready workflows

**Optimization & Evaluation:**
- **Prompt Objects** - Manipulate prompts as first-class objects instead of strings
- **Typed Examples** - Type-safe training data with automatic validation
- **Evaluation Framework** - Advanced metrics beyond simple accuracy with error-resilient pipelines
- **MIPROv2 Optimization** - Advanced Bayesian optimization with Gaussian Processes, multiple optimization strategies, auto-config presets, and storage persistence

**Production Features:**
- **Reliable JSON Extraction** - Native structured outputs for OpenAI and Gemini, Anthropic tool-based extraction, and automatic strategy selection with fallback
- **Type-Safe Configuration** - Strategy enums with automatic provider optimization (Strict/Compatible modes)
- **Smart Retry Logic** - Progressive fallback with exponential backoff for handling transient failures
- **Zero-Config Langfuse Integration** - Set env vars and get automatic OpenTelemetry traces in Langfuse
- **Performance Caching** - Schema and capability caching for faster repeated operations
- **File-based Storage** - Optimization result persistence with versioning
- **Structured Logging** - JSON and key=value formats with span tracking

## Recent Achievements

DSPy.rb has rapidly evolved from experimental to production-ready:

### Foundation
- ✅ **JSON Parsing Reliability** - Native OpenAI structured outputs with adaptive retry logic and schema-aware fallbacks
- ✅ **Type-Safe Strategy Configuration** - Provider-optimized strategy selection and enum-backed optimizer presets
- ✅ **Core Module System** - Predict, ChainOfThought, ReAct with type safety (add `dspy-code_act` for Think-Code-Observe agents)
- ✅ **Production Observability** - OpenTelemetry, New Relic, and Langfuse integration
- ✅ **Advanced Optimization** - MIPROv2 with Bayesian optimization, Gaussian Processes, and multi-mode search

### Recent Advances
- ✅ **MIPROv2 ADE Integrity (v0.29.1)** - Stratified train/val/test splits, honest precision accounting, and enum-driven `--auto` presets with integration coverage
- ✅ **Instruction Deduplication (v0.29.1)** - Candidate generation now filters repeated programs so optimization logs highlight unique strategies
- ✅ **GEPA Teleprompter (v0.29.0)** - Genetic-Pareto reflective prompt evolution with merge proposer scheduling, reflective mutation, and ADE demo parity
- ✅ **Optimizer Utilities Parity (v0.29.0)** - Bootstrap strategies, dataset summaries, and Layer 3 utilities unlock multi-predictor programs on Ruby
- ✅ **Observability Hardening (v0.29.0)** - OTLP exporter runs on a single-thread executor preventing frozen SSL contexts without blocking spans
- ✅ **Documentation Refresh (v0.29.x)** - New GEPA guide plus ADE optimization docs covering presets, stratified splits, and error-handling defaults

**Current Focus Areas:**

### Production Readiness
- 🚧 **Production Patterns** - Real-world usage validation and performance optimization
- 🚧 **Ruby Ecosystem Integration** - Rails integration, Sidekiq compatibility, deployment patterns

### Community & Adoption
- 🚧 **Community Examples** - Real-world applications and case studies
- 🚧 **Contributor Experience** - Making it easier to contribute and extend
- 🚧 **Performance Benchmarks** - Comparative analysis vs other frameworks

**v1.0 Philosophy:**
v1.0 will be released after extensive production battle-testing, not after checking off features.
The API is already stable - v1.0 represents confidence in production reliability backed by real-world validation.


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

### Prompt Engineering
- **[Signatures & Types](docs/src/core-concepts/signatures.md)** - Define typed interfaces for LLM operations
- **[Predictors](docs/src/core-concepts/predictors.md)** - Predict, ChainOfThought, ReAct, and more
- **[Modules & Pipelines](docs/src/core-concepts/modules.md)** - Compose complex multi-stage workflows
- **[Multimodal Support](docs/src/core-concepts/multimodal.md)** - Image analysis with vision-capable models
- **[Examples & Validation](docs/src/core-concepts/examples.md)** - Type-safe training data
- **[Rich Types](docs/src/advanced/complex-types.md)** - Sorbet type integration with automatic coercion for structs, enums, and arrays
- **[Composable Pipelines](docs/src/advanced/pipelines.md)** - Manual module composition patterns

### Prompt Optimization
- **[Evaluation Framework](docs/src/optimization/evaluation.md)** - Advanced metrics beyond simple accuracy
- **[Prompt Optimization](docs/src/optimization/prompt-optimization.md)** - Manipulate prompts as objects
- **[MIPROv2 Optimizer](docs/src/optimization/miprov2.md)** - Advanced Bayesian optimization with Gaussian Processes
- **[GEPA Optimizer](docs/src/optimization/gepa.md)** *(beta)* - Reflective mutation with optional reflection LMs

### Context Engineering
- **[Tools](docs/src/core-concepts/toolsets.md)** - Tool wieldint agents.
- **[Agentic Memory](docs/src/core-concepts/memory.md)** - Memory Tools & Agentic Loops
- **[RAG Patterns](docs/src/advanced/rag.md)** - Manual RAG implementation with external services

### Production Features
- **[Observability](docs/src/production/observability.md)** - Zero-config Langfuse integration with a dedicated export worker that never blocks your LLMs
- **[Storage System](docs/src/production/storage.md)** - Persistence and optimization result storage
- **[Custom Metrics](docs/src/advanced/custom-metrics.md)** - Proc-based evaluation logic 








## License
This project is licensed under the MIT License.
