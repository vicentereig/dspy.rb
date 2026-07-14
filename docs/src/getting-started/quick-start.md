---
layout: docs
name: Quick Start
description: Install DSPy.rb and run one typed prediction
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
# Quick Start

This is the canonical install-to-first-result path. It uses OpenAI for one small sentiment classifier; model output can vary.

## Your First DSPy Program {#first-program}

### 1. Create the Gemfile

Create a directory for the program and save this as `Gemfile`:

<!-- quick-start-gemfile -->
```ruby
source 'https://rubygems.org'

gem 'dspy'
gem 'dspy-openai'
```

`dspy` provides signatures and modules. `dspy-openai` provides the adapter used by the `openai/*` model identifier below. The [package and capability matrix](/dspy.rb/getting-started/packages/) lists other packages and their boundaries.

Install both gems:

<!-- quick-start-install-command -->
```bash
bundle install
```

### 2. Set the API key

Export an OpenAI API key in the same shell:

<!-- quick-start-api-key-command -->
```bash
export OPENAI_API_KEY=sk-your-key-here
```

DSPy.rb does not load `.env` files. If your application uses one, load it with your own environment library before reading the key.

### 3. Save the program

Save this exact program as `classify.rb`:

<!-- quick-start-program -->
```ruby
require 'dspy'

class Classify < DSPy::Signature
  description "Classify the sentiment of a sentence."

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

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV.fetch('OPENAI_API_KEY')
  )
end

classifier = DSPy::Predict.new(Classify)
result = classifier.call(sentence: "This book was fun to read!")

puts result.sentiment.serialize
puts result.confidence
```

### 4. Run it

<!-- quick-start-run-command -->
```bash
bundle exec ruby classify.rb
```

You will see a sentiment value followed by a confidence value. Do not depend on a particular label, confidence, or wording: those depend on the model and request. When prediction succeeds, `result.sentiment` is a `Classify::Sentiment` and `result.confidence` is a `Float`.

## What the Boundary Guarantees

The signature supplies the task description plus the input and output schemas. `DSPy::Predict` builds the provider request, converts the response to the declared Ruby types, and rejects incompatible output.

Typed output validation constrains the result shape; it does not prove that the answer is correct. Use named examples and a metric to gather evidence about model behavior; see [Examples and Datasets](/dspy.rb/core-concepts/examples/) and [Evaluation](/dspy.rb/optimization/evaluation/).

## Failure and Testing Boundaries

Because the program uses `ENV.fetch('OPENAI_API_KEY')`, running it without that variable raises Ruby's `KeyError` before `DSPy::LM` is created. An installed core gem without `dspy-openai` instead raises `DSPy::LM::MissingAdapterError` when an `openai/*` model is configured. Provider authentication, transport, rate-limit, and response-validation failures remain separate application errors; [Troubleshooting](/dspy.rb/production/troubleshooting/) lists their owning layers.

Represent expected domain uncertainty in the signature, for example with an enum value such as `Unknown`. Handle configuration and provider failures around the call rather than turning them into a model-generated result.

For deterministic tests, assert the signature schema, result classes, enum membership, and failure boundaries. Record provider calls with VCR or evaluate behavior against examples and a named metric. Avoid tests that require one exact label, confidence, or explanation from a live model.

## Key Concepts

### Modules and Agents

`DSPy::Predict` performs one typed prediction. `DSPy::ChainOfThought` adds a reasoning field, while `DSPy::ReAct` runs a bounded loop in which the model can select tools. Keep known sequencing and branches in Ruby; use an agent only when a bounded model choice is useful.

### Give an Agent a Typed Tool

Tools expose Ruby methods through Sorbet signatures:

```ruby
class WeatherTool < DSPy::Tools::Base
  tool_name 'weather'
  tool_description 'Get weather for a location'

  sig { params(location: String).returns(String) }
  def call(location:)
    "72°F and sunny in #{location}"
  end
end
```

The application owns the tool implementation, side effects, permissions, error handling, and iteration limits. `ReAct` only owns the bounded loop in which the model selects a tool or returns a result.

## Next Steps

- Learn how [signatures and types](/dspy.rb/core-concepts/signatures/) define the task contract.
- Choose among [predictors](/dspy.rb/core-concepts/predictors/).
- Compose fixed steps with [modules](/dspy.rb/core-concepts/modules/).
- Add callable capabilities with [toolsets](/dspy.rb/core-concepts/toolsets/).
