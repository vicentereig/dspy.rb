---
layout: blog
title: "DSPy.rb v0.20.0: Multi-Provider AI, Better Context Management, and Production Persistence"
description: "Major release brings Google Gemini support, fiber-local contexts, and program serialization to DSPy.rb"
date: 2025-08-26
author: Vicente Reig
tags: ["release", "features", "ruby", "ai"]
---

# DSPy.rb v0.20.0: Multi-Provider AI, Better Context Management, and Production Persistence

Three months ago, if you wanted to switch between OpenAI and Anthropic models mid-optimization, manage contexts across concurrent workflows, or persist your trained programs—you'd write a lot of glue code. Not anymore.

DSPy.rb v0.20.0 ships with Google Gemini support, fiber-local context management, and production-ready program serialization. Here's what you can build now.

## Google Gemini: Another Provider, Same API

Stefan Froelich added complete Gemini integration. Your existing DSPy code works unchanged:

```ruby
# Same signature, different model
gemini = DSPy::LM.new("gemini/gemini-1.5-flash")
openai = DSPy::LM.new("openai/gpt-4")

signature = DSPy::Signature.new("question -> answer")

# Compare responses across providers
gemini_result = DSPy::Predict.new(signature, lm: gemini).call(question: "Explain Ruby fibers")
openai_result = DSPy::Predict.new(signature, lm: openai).call(question: "Explain Ruby fibers")
```

Gemini handles multimodal inputs and includes full token tracking. Error handling covers rate limits and safety filters. No adapter code needed—it just works.

## Fiber-Local Contexts: Clean Optimization Workflows  

Before v0.20.0, switching language models during optimization meant passing LM instances around everywhere. Now you can set temporary contexts:

```ruby
fast_model = DSPy::LM.new("openai/gpt-3.5-turbo")
expensive_model = DSPy::LM.new("openai/gpt-4") 

# Use fast model for bootstrap, expensive for final optimization
DSPy.with_lm(fast_model) do
  optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.light(metric: accuracy_metric)
  
  # This uses gpt-3.5-turbo for initial examples
  result = optimizer.compile(program, trainset: train_data, valset: val_data)
  
  # Switch to expensive model for final pass
  DSPy.with_lm(expensive_model) do
    final_result = optimizer.refine(result)
  end
end
```

Fiber-local storage means no global state pollution. Your optimization workflows stay clean and predictable.

## Program Persistence: Save Your Work

Optimization takes time and tokens. Now you can save the results:

```ruby
# Train your program
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium(metric: custom_metric)
optimized_program = optimizer.compile(base_program, trainset: training_data)

# Serialize to hash (JSON-compatible)
program_state = optimized_program.to_h

# Later: restore from saved state  
restored_program = DSPy::Module.from_h(program_state)

# Same performance, no re-training
result = restored_program.call(input: "test query")
```

This works across program restarts. Store the hash in Redis, PostgreSQL, or files—your choice.

## MIPROv2 Actually Works Now

The optimizer had a nasty bootstrap hanging bug that made it unusable in production. Stefan tracked it down to malformed example creation during the bootstrap phase. Fixed in this release.

MIPROv2 now includes metric parameter support and better trace serialization. Your optimization runs complete reliably.

## What This Means for Ruby Apps

**Multi-provider flexibility**: Switch between OpenAI, Anthropic, and Gemini based on cost, speed, or capabilities. Same code, different economics.

**Cleaner optimization workflows**: Set contexts temporarily without polluting global state. Particularly useful in Rails apps or concurrent services.

**Production persistence**: Save expensive optimization results. Deploy trained programs without re-running optimization.

**Better reliability**: MIPROv2 optimization actually completes now. Essential for production use.

## What's Coming

Token efficiency is next. We're exploring BAML-inspired approaches to reduce token usage by 50-70% while improving accuracy for complex nested structures.

OpenTelemetry integration is in progress—proper observability for production AI workflows.

Storage system improvements will bring Rails-like patterns to program management.

## Try It

```ruby
gem install dspy
```

The [documentation](https://dspy.vicentereig.com) covers everything. The [examples](https://github.com/vicentereig/dspy.rb/tree/main/examples) show real usage patterns.

Found a bug or want a feature? [Open an issue](https://github.com/vicentereig/dspy.rb/issues). Pull requests welcome.

---

*DSPy.rb v0.20.0 includes 25 commits from Vicente Reig and Stefan Froelich, with 71 files changed. Full changelog on [GitHub](https://github.com/vicentereig/dspy.rb/releases/tag/v0.20.0).*