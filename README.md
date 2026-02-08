# DSPy.rb

[![Gem Version](https://img.shields.io/gem/v/dspy)](https://rubygems.org/gems/dspy)
[![Total Downloads](https://img.shields.io/gem/dt/dspy)](https://rubygems.org/gems/dspy)
[![Build Status](https://img.shields.io/github/actions/workflow/status/vicentereig/dspy.rb/ruby.yml?branch=main&label=build)](https://github.com/vicentereig/dspy.rb/actions/workflows/ruby.yml)
[![Documentation](https://img.shields.io/badge/docs-oss.vicente.services%2Fdspy.rb-blue)](https://oss.vicente.services/dspy.rb/)
[![Discord](https://img.shields.io/discord/1161519468141355160?label=discord&logo=discord&logoColor=white)](https://discord.gg/zWBhrMqn)

**Build reliable LLM applications in idiomatic Ruby using composable, type-safe modules.**

DSPy.rb is the Ruby port of Stanford's [DSPy](https://dspy.ai). Instead of wrestling with brittle prompt strings, you define typed signatures and let the framework handle the rest. Prompts become functions. LLM calls become predictable.

```ruby
require 'dspy'

DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

class Summarize < DSPy::Signature
  description "Summarize the given text in one sentence."

  input do
    const :text, String
  end

  output do
    const :summary, String
  end
end

summarizer = DSPy::Predict.new(Summarize)
result = summarizer.call(text: "DSPy.rb brings structured LLM programming to Ruby...")
puts result.summary
```

That's it. No prompt templates. No JSON parsing. No prayer-based error handling.

## Installation

```ruby
# Gemfile
gem 'dspy'
gem 'dspy-openai'     # For OpenAI, OpenRouter, or Ollama
# gem 'dspy-anthropic' # For Claude
# gem 'dspy-gemini'    # For Gemini
# gem 'dspy-ruby_llm'  # For 12+ providers via RubyLLM
```

```bash
bundle install
```

## Quick Start

### Configure Your LLM

```ruby
# OpenAI
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini',
                      api_key: ENV['OPENAI_API_KEY'],
                      structured_outputs: true)
end

# Anthropic Claude
DSPy.configure do |c|
  c.lm = DSPy::LM.new('anthropic/claude-sonnet-4-20250514',
                      api_key: ENV['ANTHROPIC_API_KEY'])
end

# Google Gemini
DSPy.configure do |c|
  c.lm = DSPy::LM.new('gemini/gemini-2.5-flash',
                      api_key: ENV['GEMINI_API_KEY'])
end

# Ollama (local, free)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('ollama/llama3.2')
end

# OpenRouter (200+ models)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free',
                      api_key: ENV['OPENROUTER_API_KEY'])
end
```

### Define a Signature

Signatures are typed contracts for LLM operations. Define inputs, outputs, and let DSPy handle the prompt:

```ruby
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
    const :sentence, String, description: 'The sentence to analyze'
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

classifier = DSPy::Predict.new(Classify)
result = classifier.call(sentence: "This book was super fun to read!")

result.sentiment    # => #<Sentiment::Positive>
result.confidence   # => 0.92
```

### Chain of Thought

For complex reasoning, use `ChainOfThought` to get step-by-step explanations:

```ruby
solver = DSPy::ChainOfThought.new(MathProblem)
result = solver.call(problem: "If a train travels 120km in 2 hours, what's its speed?")

result.reasoning  # => "Speed = Distance / Time = 120km / 2h = 60km/h"
result.answer     # => "60 km/h"
```

### ReAct Agents

Build agents that use tools to accomplish tasks:

```ruby
class SearchTool < DSPy::Tools::Base
  tool_name "search"
  tool_description "Search for information"

  sig { params(query: String).returns(String) }
  def call(query:)
    # Your search implementation
    "Result 1, Result 2"
  end
end

agent = DSPy::ReAct.new(ResearchTask, tools: [SearchTool.new], max_iterations: 5)
result = agent.call(question: "What's the latest on Ruby 3.4?")
```

## What's Included

**Core Modules**: Predict, ChainOfThought, ReAct agents, and composable pipelines.

**Type Safety**: Sorbet-based runtime validation. Enums, unions, nested structs—all work.

**Multimodal**: Image analysis with `DSPy::Image` for vision-capable models.

**Observability**: Zero-config Langfuse integration via OpenTelemetry. Non-blocking, production-ready.

**Optimization**: MIPROv2 (Bayesian optimization) and GEPA (genetic evolution) for prompt tuning.

**Provider Support**: OpenAI, Anthropic, Gemini, Ollama, and OpenRouter via official SDKs.

## Documentation

**[Full Documentation](https://oss.vicente.services/dspy.rb/)** — Getting started, core concepts, advanced patterns.

**[llms.txt](https://oss.vicente.services/dspy.rb/llms.txt)** — LLM-friendly reference for AI assistants.

### Claude Skill

A [Claude Skill](https://github.com/vicentereig/dspy-rb-skill) is available to help you build DSPy.rb applications:

```bash
# Claude Code
git clone https://github.com/vicentereig/dspy-rb-skill ~/.claude/skills/dspy-rb
```

For Claude.ai Pro/Max, download the [skill ZIP](https://github.com/vicentereig/dspy-rb-skill/archive/refs/heads/main.zip) and upload via Settings > Skills.

## Examples

The [examples/](examples/) directory has runnable code for common patterns:

- Sentiment classification
- ReAct agents with tools
- Image analysis
- Prompt optimization

```bash
bundle exec ruby examples/first_predictor.rb
```

## Optional Gems

DSPy.rb ships sibling gems for features with heavier dependencies. Add them as needed:

| Gem | What it does |
| --- | --- |
| `dspy-datasets` | Dataset helpers, Parquet/Polars tooling |
| `dspy-evals` | Evaluation harness with metrics and callbacks |
| `dspy-miprov2` | Bayesian optimization for prompt tuning |
| `dspy-gepa` | Genetic-Pareto prompt evolution |
| `dspy-o11y-langfuse` | Auto-configure Langfuse tracing |
| `dspy-code_act` | Think-Code-Observe agents |
| `dspy-deep_search` | Production DeepSearch with Exa |

See [the full list](https://oss.vicente.services/dspy.rb/getting-started/installation/) in the docs.

## Contributing

Feedback is invaluable. If you encounter issues, [open an issue](https://github.com/vicentereig/dspy.rb/issues). For suggestions, [start a discussion](https://github.com/vicentereig/dspy.rb/discussions).

Want to contribute code? Reach out: hey at vicente.services

## License

MIT License.
