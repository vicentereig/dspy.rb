# DSPy.rb

[![Gem Version](https://img.shields.io/gem/v/dspy)](https://rubygems.org/gems/dspy)
[![Total Downloads](https://img.shields.io/gem/dt/dspy)](https://rubygems.org/gems/dspy)
[![Build Status](https://img.shields.io/github/actions/workflow/status/vicentereig/dspy.rb/ruby.yml?branch=main&label=build)](https://github.com/vicentereig/dspy.rb/actions/workflows/ruby.yml)
[![Documentation](https://img.shields.io/badge/docs-oss.vicente.services%2Fdspy.rb-blue)](https://oss.vicente.services/dspy.rb/)
[![Discord](https://img.shields.io/discord/1161519468141355160?label=discord&logo=discord&logoColor=white)](https://discord.gg/zWBhrMqn)

**Program typed LLM systems in Ruby.**

DSPy.rb brings [DSPy](https://dspy.ai)'s signature, module, agent, and optimizer model to Ruby, with Sorbet types and Ruby-native integrations. A signature declares a task as typed inputs and outputs. Modules choose how to run it. Ruby composes modules into programs, and `ReAct` adds a bounded tool-using loop when the model should choose the next action. DSPy.rb builds the provider request and validates the result.

The `1.x` series is the current stable release line.

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

No hand-maintained prompt templates. No JSON parsing. No prayer-based error handling.

## Installation

```ruby
# Gemfile
gem 'dspy'
gem 'dspy-openai'     # For OpenAI, OpenRouter, or Ollama
```

Choose other provider and optional gems from the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/). The matrix separates install availability from provider, model, and SDK limitations.

```bash
bundle install
```

## Quick Start

### Configure Your LLM

Configure one provider. The examples below show the supported model identifier formats.

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

# OpenRouter
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free',
                      api_key: ENV['OPENROUTER_API_KEY'])
end
```

### Define a Signature

A signature defines the fields an LLM operation accepts and returns. `DSPy::Predict` uses it to make the request and validate the result:

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

Use `ChainOfThought` when the result should include the model's reasoning:

```ruby
solver = DSPy::ChainOfThought.new(MathProblem)
result = solver.call(problem: "If a train travels 120km in 2 hours, what's its speed?")

result.reasoning  # => "Speed = Distance / Time = 120km / 2h = 60km/h"
result.answer     # => "60 km/h"
```

### ReAct Agents

`ReAct` lets a module call Ruby tools while working on a task:

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

| Capability | What it provides |
| --- | --- |
| Modules | `Predict`, `ChainOfThought`, bounded ReAct agents, and custom modules |
| Programs | Compose modules with ordinary Ruby control flow |
| Tools | Expose typed Ruby operations to ReAct agents |
| Runtime types | Sorbet validation for enums, unions, and nested structs |
| Multimodal input | `DSPy::Image` support for vision-capable models |
| Observability | Optional `dspy-o11y-langfuse` integration with an asynchronous OpenTelemetry span exporter |
| Optimization | MIPROv2 Bayesian optimization and GEPA genetic-Pareto evolution |
| Providers | OpenAI, Anthropic, Gemini, Ollama, and OpenRouter through their SDKs |

## Documentation

**[Full Documentation](https://oss.vicente.services/dspy.rb/)** — Installation, core concepts, and advanced usage.

**[llms.txt](https://oss.vicente.services/dspy.rb/llms.txt)** — Reference formatted for AI assistants.

### Claude Skill

The [Claude Skill](https://github.com/vicentereig/dspy-rb-skill) provides DSPy.rb guidance in Claude Code and Claude.ai:

```bash
# Claude Code — install from the vicentereig/engineering marketplace
claude install-skill vicentereig/engineering --skill dspy-rb
```

For Claude.ai Pro/Max, download the [skill ZIP](https://github.com/vicentereig/dspy-rb-skill/archive/refs/heads/main.zip) and upload via Settings > Skills.

## Examples

The [examples/](examples/) directory contains runnable examples:

- Sentiment classification
- ReAct agents with tools
- Image analysis
- Prompt optimization

```bash
bundle exec ruby examples/basic_search_agent.rb
```

## Optional Gems

Provider adapters, optimizers, observability exporters, datasets, and code-executing agents can add their own dependencies. Use the [authoritative package matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for exact gem names, require behavior, support labels, and capability boundaries.

## Contributing

For bugs, [open an issue](https://github.com/vicentereig/dspy.rb/issues). For suggestions, [start a discussion](https://github.com/vicentereig/dspy.rb/discussions).

Want to contribute code? Reach out: hey at vicente.services

## License

MIT License.
