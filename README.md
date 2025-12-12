# DSPy.rb

[![Gem Version](https://img.shields.io/gem/v/dspy)](https://rubygems.org/gems/dspy)
[![Total Downloads](https://img.shields.io/gem/dt/dspy)](https://rubygems.org/gems/dspy)
[![Build Status](https://img.shields.io/github/actions/workflow/status/vicentereig/dspy.rb/ruby.yml?branch=main&label=build)](https://github.com/vicentereig/dspy.rb/actions/workflows/ruby.yml)
[![Documentation](https://img.shields.io/badge/docs-oss.vicente.services%2Fdspy.rb-blue)](https://oss.vicente.services/dspy.rb/)
[![Discord](https://img.shields.io/discord/1161519468141355160?label=discord&logo=discord&logoColor=white)](https://discord.gg/zWBhrMqn)

> [!NOTE]
> The core Prompt Engineering Framework is production-ready with
> comprehensive documentation. I am focusing now on educational content on systematic Prompt Optimization and Context Engineering.
> Your feedback is invaluable. if you encounter issues, please open an [issue](https://github.com/vicentereig/dspy.rb/issues). If you have suggestions, open a [new thread](https://github.com/vicentereig/dspy.rb/discussions).  
> 
> If you want to contribute, feel free to reach out to me to coordinate efforts: hey at vicente.services
>

**Build reliable LLM applications in idiomatic Ruby using composable, type-safe modules.**

DSPy.rb is the Ruby-first surgical port of Stanford's [DSPy paradigm](https://github.com/stanfordnlp/dspy). It delivers structured LLM programming, prompt engineering, and context engineering in the language we love. Instead of wrestling with brittle prompt strings, you define typed signatures in idiomatic Ruby and compose workflows and agents that actually behave.

**Prompts are just functions.** Traditional prompting is like writing code with string concatenation: it works until it doesn't. DSPy.rb brings you the programming approach pioneered by [dspy.ai](https://dspy.ai/): define modular signatures and let the framework deal with the messy bits.

While we implement the same signatures, predictors, and optimization algorithms as the original library, DSPy.rb leans hard into Ruby conventions with Sorbet-based typing, ReAct loops, and production-ready integrations like non-blocking OpenTelemetry instrumentation.

**What you get?** Ruby LLM applications that scale and don't break when you sneeze.

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

### Your First Reliable Predictor

```ruby
require 'dspy'

# Configure DSPy globally to use your fave LLM (you can override per predictor).
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

# Wire it to the simplest prompting technique: a prediction loop.
classify = DSPy::Predict.new(Classify)
# it may raise an error if you mess the inputs or your LLM messes the outputs.
result = classify.call(sentence: "This book was super fun to read!")

puts result.sentiment    # => #<Sentiment::Positive>  
puts result.confidence   # => 0.85
```

Save this as `examples/first_predictor.rb` and run it with:

```bash
bundle exec ruby examples/first_predictor.rb
```

### Sibling Gems

DSPy.rb ships multiple gems from this monorepo so you can opt into features with heavier dependency trees (e.g., datasets pull in Polars/Arrow, MIPROv2 requires `numo-*` BLAS bindings) only when you need them. Add these alongside `dspy`:

| Gem | Description | Status |
| --- | --- | --- |
| `dspy-schema` | Exposes `DSPy::TypeSystem::SorbetJsonSchema` for downstream reuse. (Still required by the core `dspy` gem; extraction lets other projects depend on it directly.) | **Stable** (v1.0.0) |
| `dspy-openai` | Packages the OpenAI/OpenRouter/Ollama adapters plus the official SDK guardrails. Install whenever you call `openai/*`, `openrouter/*`, or `ollama/*`. [Adapter README](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/openai/README.md) | **Stable** (v1.0.0) |
| `dspy-anthropic` | Claude adapters, streaming, and structured-output helpers behind the official `anthropic` SDK. [Adapter README](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/anthropic/README.md) | **Stable** (v1.0.0) |
| `dspy-gemini` | Gemini adapters with multimodal + tool-call support via `gemini-ai`. [Adapter README](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/gemini/README.md) | **Stable** (v1.0.0) |
| `dspy-ruby_llm` | Unified access to 12+ LLM providers (OpenAI, Anthropic, Gemini, Bedrock, Ollama, DeepSeek, etc.) via [RubyLLM](https://rubyllm.com). [Adapter README](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/ruby_llm/README.md) | **Stable** (v0.1.0) |
| `dspy-code_act` | Think-Code-Observe agents that synthesize and execute Ruby safely. (Add the gem or set `DSPY_WITH_CODE_ACT=1` before requiring `dspy/code_act`.) | **Stable** (v1.0.0) |
| `dspy-datasets` | Dataset helpers plus Parquet/Polars tooling for richer evaluation corpora. (Toggle via `DSPY_WITH_DATASETS`.) | **Stable** (v1.0.0) |
| `dspy-evals` | High-throughput evaluation harness with metrics, callbacks, and regression fixtures. (Toggle via `DSPY_WITH_EVALS`.) | **Stable** (v1.0.0) |
| `dspy-miprov2` | Bayesian optimization + Gaussian Process backend for the MIPROv2 teleprompter. (Install or export `DSPY_WITH_MIPROV2=1` before requiring the teleprompter.) | **Stable** (v1.0.0) |
| `dspy-gepa` | `DSPy::Teleprompt::GEPA`, reflection loops, experiment tracking, telemetry adapters. (Install or set `DSPY_WITH_GEPA=1`.) | **Stable** (v1.0.0) |
| `gepa` | GEPA optimizer core (Pareto engine, telemetry, reflective proposer). | **Stable** (v1.0.0) |
| `dspy-o11y` | Core observability APIs: `DSPy::Observability`, async span processor, observation types. (Install or set `DSPY_WITH_O11Y=1`.) | **Stable** (v1.0.0) |
| `dspy-o11y-langfuse` | Auto-configures DSPy observability to stream spans to Langfuse via OTLP. (Install or set `DSPY_WITH_O11Y_LANGFUSE=1`.) | **Stable** (v1.0.0) |
| `dspy-deep_search` | Production DeepSearch loop with Exa-backed search/read, token budgeting, and instrumentation (Issue #163). | **Stable** (v1.0.0) |
| `dspy-deep_research` | Planner/QA orchestration atop DeepSearch plus the memory supervisor used by the CLI example. | **Stable** (v1.0.0) |
| `sorbet-toon` | Token-Oriented Object Notation (TOON) codec, prompt formatter, and Sorbet mixins for BAML/TOON Enhanced Prompting. [Sorbet::Toon README](https://github.com/vicentereig/dspy.rb/blob/main/lib/sorbet/toon/README.md) | **Alpha** (v0.1.0) |

**Provider adapters:** Add `dspy-openai`, `dspy-anthropic`, and/or `dspy-gemini` next to `dspy` in your Gemfile depending on which `DSPy::LM` providers you call. Each gem already depends on the official SDK (`openai`, `anthropic`, `gemini-ai`), and DSPy auto-loads the adapters when the gem is present—no extra `require` needed.

Set the matching `DSPY_WITH_*` environment variables (see `Gemfile`) to include or exclude each sibling gem when running Bundler locally (for example `DSPY_WITH_GEPA=1` or `DSPY_WITH_O11Y_LANGFUSE=1`). Refer to `adr/013-dependency-tree.md` for the full dependency map and roadmap.
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

**Developer Experience:** Official clients, multimodal coverage, and observability baked in.
<details>
<summary>Expand for everything included</summary>

- LLM provider support using official Ruby clients:
  - [OpenAI Ruby](https://github.com/openai/openai-ruby) with vision model support
  - [Anthropic Ruby SDK](https://github.com/anthropics/anthropic-sdk-ruby) with multimodal capabilities
  - [Google Gemini API](https://ai.google.dev/) with native structured outputs
  - [Ollama](https://ollama.com/) via OpenAI compatibility layer for local models
- **Multimodal Support** - Complete image analysis with DSPy::Image, type-safe bounding boxes, vision-capable models
- Runtime type checking with [Sorbet](https://sorbet.org/) including T::Enum and union types
- Type-safe tool definitions for ReAct agents
- Comprehensive instrumentation and observability
</details>

**Core Building Blocks:** Predictors, agents, and pipelines wired through type-safe signatures.
<details>
<summary>Expand for everything included</summary>

- **Signatures** - Define input/output schemas using Sorbet types with T::Enum and union type support
- **Predict** - LLM completion with structured data extraction and multimodal support
- **Chain of Thought** - Step-by-step reasoning for complex problems with automatic prompt optimization
- **ReAct** - Tool-using agents with type-safe tool definitions and error recovery
- **Module Composition** - Combine multiple LLM calls into production-ready workflows
</details>

**Optimization & Evaluation:** Treat prompt optimization like a real ML workflow.
<details>
<summary>Expand for everything included</summary>

- **Prompt Objects** - Manipulate prompts as first-class objects instead of strings
- **Typed Examples** - Type-safe training data with automatic validation
- **Evaluation Framework** - Advanced metrics beyond simple accuracy with error-resilient pipelines
- **MIPROv2 Optimization** - Advanced Bayesian optimization with Gaussian Processes, multiple optimization strategies, auto-config presets, and storage persistence
</details>

**Production Features:** Hardened behaviors for teams shipping actual products.
<details>
<summary>Expand for everything included</summary>

- **Reliable JSON Extraction** - Native structured outputs for OpenAI and Gemini, Anthropic tool-based extraction, and automatic strategy selection with fallback
- **Type-Safe Configuration** - Strategy enums with automatic provider optimization (Strict/Compatible modes)
- **Smart Retry Logic** - Progressive fallback with exponential backoff for handling transient failures
- **Zero-Config Langfuse Integration** - Set env vars and get automatic OpenTelemetry traces in Langfuse
- **Performance Caching** - Schema and capability caching for faster repeated operations
- **File-based Storage** - Optimization result persistence with versioning
- **Structured Logging** - JSON and key=value formats with span tracking
</details>

## Recent Achievements

DSPy.rb has gone from experimental to production-ready in three fast releases.
<details>
<summary>Expand for the full changelog highlights</summary>

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
</details>

**Current Focus Areas:** Closing the loop on production patterns and community adoption ahead of v1.0.
<details>
<summary>Expand for the roadmap</summary>

### Production Readiness
- 🚧 **Production Patterns** - Real-world usage validation and performance optimization
- 🚧 **Ruby Ecosystem Integration** - Rails integration, Sidekiq compatibility, deployment patterns

### Community & Adoption
- 🚧 **Community Examples** - Real-world applications and case studies
- 🚧 **Contributor Experience** - Making it easier to contribute and extend
- 🚧 **Performance Benchmarks** - Comparative analysis vs other frameworks
</details>

**v1.0 Philosophy:** v1.0 lands after battle-testing, not checkbox bingo. The API is already stable; the milestone marks production confidence.


## Documentation

📖 **[Complete Documentation Website](https://oss.vicente.services/dspy.rb/)**

### LLM-Friendly Documentation

For LLMs and AI assistants working with DSPy.rb:
- **[llms.txt](https://oss.vicente.services/dspy.rb/llms.txt)** - Concise reference optimized for LLMs
- **[llms-full.txt](https://oss.vicente.services/dspy.rb/llms-full.txt)** - Comprehensive API documentation

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
