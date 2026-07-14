---
layout: docs
name: Python DSPy Comparison
description: Compare the programming models and current scope of DSPy and DSPy.rb
date: 2025-07-11 00:00:00 +0000
---
# DSPy and DSPy.rb

DSPy.rb began as a port and still follows DSPy's central model: signatures declare tasks, modules choose execution strategies, ordinary code composes programs, and optimizers compile supported parameters against examples and metrics. It now evolves as an independent Ruby-native implementation, not an API-compatible port or an official DSPy project.

Upstream DSPy changes faster and includes modules, integrations, and optimizers that DSPy.rb may not implement. Use the [official DSPy documentation](https://dspy.ai/) for the current Python API.

## Shared Concepts

Both projects use:

- Signatures for task instructions and typed fields.
- `Predict` and `ChainOfThought` modules.
- `ReAct` for a model-directed tool loop.
- Examples and metrics for evaluation.
- MIPROv2 and GEPA for instruction and demonstration optimization.
- Program serialization and observability concepts.

The names do not imply identical runtime behavior or serialized formats.

## DSPy.rb Scope

DSPy.rb currently provides:

- Sorbet-backed signatures and runtime coercion.
- OpenAI, Anthropic, Gemini, Ollama, OpenRouter, and RubyLLM adapter packages.
- `Predict`, `ChainOfThought`, and bounded `ReAct` agents in core.
- Optional CodeAct, evaluation, MIPROv2, GEPA, dataset, and observability gems.
- Typed tools and toolsets.
- Program storage, registry, events, and OpenTelemetry integration.

Ruby control flow remains the normal way to build a fixed pipeline. Use an agent only when the model should choose among available actions.

## Differences to Expect

- Python examples cannot be translated mechanically; constructor options and result objects differ.
- Upstream modules such as `ProgramOfThought`, `RLM`, or experimental ReAct variants may have no Ruby equivalent.
- Provider and tool integrations differ by ecosystem.
- DSPy.rb uses Sorbet and Ruby objects where upstream uses Python typing and Pydantic-oriented structures.
- Optimizer implementations may support different knobs, traces, and persistence formats.

## Porting a Program

1. Preserve the signature's task and field semantics.
2. Rebuild the module composition in Ruby rather than translating syntax line by line.
3. Replace Python tools and retrieval clients with application-owned Ruby implementations.
4. Recreate examples and metrics with `DSPy::Example` and `DSPy::Evals`.
5. Run a baseline before introducing an optimizer.
6. Verify provider requests, tool side effects, and serialized artifacts in the Ruby environment.

Feature parity is not the target. The useful test is whether the Ruby program exposes the same task boundary and meets the same evaluated behavior.
