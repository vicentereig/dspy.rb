---
layout: blog
title: "Fiber-Local LM Contexts: Temporary Model Selection in Ruby"
description: "DSPy.with_lm applies a temporary language model override to the current fiber, with explicit precedence and exception-safe restoration."
date: 2025-08-26
author: "Vicente Reig"
category: "Features"
reading_time: "3 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/fiber-local-lm-contexts/"
image: /images/og/fiber-local-lm-contexts.png
---

DSPy.rb v0.20.0 added `DSPy.with_lm`, contributed by Stefan Froelich. It temporarily changes the model used by DSPy modules in the current fiber, then restores the previous selection when the block exits.

That is useful when the same program needs a different model for an evaluation run, a particular task, or one concurrent branch. It avoids passing an LM through every module call.

## Apply a temporary model

```ruby
require 'dspy'

DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])
end

class SentimentAnalyzer < DSPy::Module
  def initialize
    @predictor = DSPy::Predict.new(SentimentSignature)
  end

  def call(text:)
    @predictor.forward(text: text)
  end
end

analyzer = SentimentAnalyzer.new
fast_model = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

default_result = analyzer.call(text: "This is amazing!")

fast_result = DSPy.with_lm(fast_model) do
  analyzer.call(text: "This is amazing!")
end

default_again = analyzer.call(text: "This is amazing!")
```

The first and third calls resolve the global LM. The call inside `with_lm` resolves `fast_model`. The method returns the block's value, so no extra result wrapper is needed.

## Resolution order

DSPy modules resolve an LM in this order:

1. An LM configured on the module instance.
2. The current fiber's `DSPy.with_lm` value.
3. The global `DSPy.config.lm`.

An instance-level choice is therefore explicit and final for that module:

```ruby
DSPy.configure { |config| config.lm = global_model }

analyzer = SentimentAnalyzer.new
analyzer.config.lm = instance_model

DSPy.with_lm(temporary_model) do
  analyzer.call(text: "Test") # uses instance_model
end
```

Use an instance LM when a module always belongs to one model. Use `with_lm` when the caller owns a temporary choice that should flow through nested modules without changing their constructors.

## Nesting and exceptions

`DSPy.with_lm` records the previous fiber-local value and restores it in an `ensure` block. Nested overrides unwind in order, including when a call raises:

```ruby
DSPy.configure { |config| config.lm = global_model }

DSPy.with_lm(model_a) do
  puts DSPy.current_lm # => model_a

  begin
    DSPy.with_lm(model_b) do
      puts DSPy.current_lm # => model_b
      raise "Something went wrong!"
    end
  rescue RuntimeError
    puts DSPy.current_lm # => model_a
  end
end

puts DSPy.current_lm # => global_model
```

The restoration covers DSPy's model-selection state. It does not undo side effects performed inside the block.

## Concurrent model selection

Sibling Async tasks can select different models without rewriting the module graph:

```ruby
require 'async'

DSPy.configure { |config| config.lm = default_model }

Async do |task|
  first = task.async do
    DSPy.with_lm(openai_model) do
      analyzer.call(text: "Analyze with OpenAI")
    end
  end

  second = task.async do
    DSPy.with_lm(anthropic_model) do
      analyzer.call(text: "Analyze with Anthropic")
    end
  end

  [first.wait, second.wait]
end
```

The override belongs to each fiber. Concurrent execution still depends on the application creating sibling tasks and on the provider transports yielding cooperatively. `with_lm` supplies context isolation, not scheduling.

## Use it at a clear boundary

Good boundaries include one evaluation run, one request branch, or one batch whose model choice is part of the experiment:

```ruby
scores = models.to_h do |name, model|
  result = DSPy.with_lm(model) do
    evaluator = DSPy::Evals.new(program, metric: metric)
    evaluator.evaluate(test_set)
  end

  [name, result.score]
end
```

Avoid wrapping unrelated application behavior merely to save an argument. A large implicit scope makes model selection harder to inspect, especially when a nested module also has an instance-level LM.

`DSPy.with_lm` is a small piece of runtime context. The program remains ordinary Ruby, and the precedence rules stay visible when the model choice matters.
