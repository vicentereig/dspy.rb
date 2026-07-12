---
layout: blog
title: "DSPy.rb v0.20.0: Gemini, Fiber-Local Context, and Program Storage"
description: "DSPy.rb v0.20.0 added Google Gemini support, fiber-local LM overrides, and storage for serializable optimized programs."
date: 2025-08-26
author: Vicente Reig
tags: ["release", "features", "ruby", "ai"]
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/dspy-rb-0-20-0-release-announcement/"
image: /images/og/dspy-rb-0-20-0-release-announcement.png
---

DSPy.rb v0.20.0 added three pieces of infrastructure that had previously required application code: a Gemini adapter, fiber-local LM overrides, and storage for optimized program state.

## Google Gemini

Stefan Froelich contributed the Gemini adapter. A signature and module can move between supported providers without changing their task contract:

```ruby
class AnswerQuestion < DSPy::Signature
  input { const :question, String }
  output { const :answer, String }
end

gemini = DSPy::LM.new("gemini/gemini-1.5-flash")
openai = DSPy::LM.new("openai/gpt-4o-mini")

predictor = DSPy::Predict.new(AnswerQuestion)

gemini_answer = DSPy.with_lm(gemini) do
  predictor.call(question: "Explain Ruby fibers")
end
openai_answer = DSPy.with_lm(openai) do
  predictor.call(question: "Explain Ruby fibers")
end
```

The adapter supports text, inline images, usage metadata, and DSPy.rb's structured response path. Provider capabilities still differ; changing the model does not make the providers identical.

## Fiber-Local LM Overrides

`DSPy.with_lm` temporarily overrides the configured model for the current fiber. Nested overrides restore the previous model when the block exits, including after an exception.

```ruby
fast_lm = DSPy::LM.new("openai/gpt-4o-mini")
review_lm = DSPy::LM.new("anthropic/claude-3-5-sonnet-latest")

draft = DSPy.with_lm(fast_lm) { writer.call(topic: "Ruby fibers") }
review = DSPy.with_lm(review_lm) { critic.call(text: draft.text) }
```

The override isolates configuration. It does not create concurrent work; the surrounding Ruby program still decides what runs and when.

## Program Storage

Optimization is expensive enough that throwing away the result is a poor default. `DSPy::Storage::ProgramStorage` writes serializable program state and optimization metadata to JSON:

```ruby
storage = DSPy::Storage::ProgramStorage.new(storage_path: "./dspy_storage")

saved = storage.save_program(
  optimized_program,
  optimization_result,
  metadata: { dataset: "support-v2" }
)

loaded = storage.load_program(saved.program_id)
program = loaded.program
```

Deserialization requires the saved program class to be loaded and to implement `.from_h`. The storage serializer captures a small common state for compatible built-in programs; it cannot infer arbitrary state from a custom Ruby object.

## MIPROv2 Repairs

This release also fixed failures in the MIPROv2 path and made the optimizer usable against DSPy.rb modules. As always, an optimizer still needs representative examples and a metric that expresses acceptable behavior. A successful run is evidence for that dataset and metric, not a transferable quality guarantee.

## Upgrade

```bash
bundle update dspy
```

Install the provider gem you use, such as `dspy-gemini`, alongside the core `dspy` gem.
