# DSPy.rb

[![Gem Version](https://img.shields.io/gem/v/dspy)](https://rubygems.org/gems/dspy)
[![Total Downloads](https://img.shields.io/gem/dt/dspy)](https://rubygems.org/gems/dspy)
[![Build Status](https://img.shields.io/github/actions/workflow/status/vicentereig/dspy.rb/ruby.yml?branch=main&label=build)](https://github.com/vicentereig/dspy.rb/actions/workflows/ruby.yml)
[![Documentation](https://img.shields.io/badge/docs-oss.vicente.services%2Fdspy.rb-blue)](https://oss.vicente.services/dspy.rb/)
[![Discord](https://img.shields.io/discord/1161519468141355160?label=discord&logo=discord&logoColor=white)](https://discord.gg/zWBhrMqn)

**Program typed LLM systems in Ruby.**

DSPy.rb brings [DSPy](https://dspy.ai)'s signature, module, agent, and optimizer model to Ruby, with Sorbet types and Ruby-native integrations. A signature declares a task as typed inputs and outputs. A module chooses how to execute it. Ruby composes modules into programs, while `ReAct` adds a bounded loop when the model should choose the next action. DSPy.rb builds the provider request and validates the returned shape.

The `1.x` series is the current stable release line.

In a configured application, the task contract and call look like this:

```ruby
class Classify < DSPy::Signature
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

classifier = DSPy::Predict.new(Classify)
result = classifier.call(sentence: "This book was fun to read!")
```

Define a typed task contract, not a hand-maintained output template. Receive validated Ruby values, not application-owned JSON parsing. Handle explicit configuration, transport, and validation errors—not crossed fingers.

## Start Here

The [Quick Start](https://oss.vicente.services/dspy.rb/getting-started/quick-start/) is the complete supported path: install the core and provider gems, configure a key, save a program, and run it.

Use [Installation](https://oss.vicente.services/dspy.rb/getting-started/installation/) to choose a provider. The [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) records exact gem names, require behavior, support labels, and model or SDK boundaries.

## Mental Model

- A `DSPy::Signature` defines the task contract.
- `DSPy::Predict` and other modules choose an execution strategy.
- Ordinary Ruby owns fixed sequencing, branching, persistence, permissions, and failure policy.
- Results cross a runtime validation boundary; validation establishes shape, not factual correctness.

### ReAct Agents

Use `ReAct` when the model needs to choose among typed Ruby tools inside an iteration bound. The application still owns tool authorization, side effects, budgets, and errors. See [Predictors](https://oss.vicente.services/dspy.rb/core-concepts/predictors/) and [Toolsets](https://oss.vicente.services/dspy.rb/core-concepts/toolsets/).

## Explore

- [Documentation](https://oss.vicente.services/dspy.rb/) — task-oriented guides and reference
- [Examples](examples/) — repository demos indexed by capability and prerequisites
- [llms.txt](https://oss.vicente.services/dspy.rb/llms.txt) — generated reference for AI assistants

Provider adapters, optimizers, observability exporters, datasets, and code-executing agents are separate packages when they add dependencies. Check the package matrix before selecting one; package availability does not guarantee uniform provider or model behavior.

## Contributing

For bugs, [open an issue](https://github.com/vicentereig/dspy.rb/issues). For suggestions, [start a discussion](https://github.com/vicentereig/dspy.rb/discussions).

Want to contribute code? Reach out: hey at vicente.services

## License

MIT License.
