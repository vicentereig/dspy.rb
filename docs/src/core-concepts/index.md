---
layout: docs
title: "DSPy.rb Core Concepts: Signatures, Modules, and Predictors"
description: "Learn how signatures, modules, Ruby programs, agents, tools, evaluation, and optimization fit together in DSPy.rb."
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-13 00:00:00 +0000
---
# Core Concepts

Start with a signature, then choose a module. Compose modules with Ruby when the control flow is known. Use `ReAct` when the model should choose among typed tools.

## The Programming Model

### [Signatures](./signatures/)
Define what your LLM operations should do - the inputs and outputs. Think of them as type-safe contracts for AI operations.

### [Modules](./modules/)
Choose how to execute a signature. Compose modules with ordinary Ruby control flow to build a program.

### [Module Runtime Context](./module-runtime-context/)
Control language-model resolution and lifecycle callbacks for module calls.

### [Event System](./events/)
Emit structured telemetry with `DSPy.event`, add global listeners, and scope subscriptions directly to the modules that care.

### Application State
Keep conversation history, user preferences, checkpoints, and other durable state in application-owned storage. Pass the state a module needs through typed inputs.

### [Toolsets](./toolsets/)
Group related typed operations for a `ReAct` agent. Toolsets expose capabilities; application code remains responsible for permissions and side effects.

### [Predictors](./predictors/)
Connect your modules to language models with different strategies like chain-of-thought reasoning or tool use.

### [CodeAct](./codeact/) _(requires the `dspy-code_act` gem)_
Run a bounded Think-Code-Observe agent. The host application supplies the executor, isolation policy, permissions, and limits.

### [Multimodal](./multimodal/)
Work with text and image inputs to build vision-capable AI applications using multimodal language models.

### [Examples](./examples/)
Learn from real-world use cases and patterns that demonstrate best practices for common scenarios.

## Start Learning

We recommend reading through these concepts in order:

1. Start with [Signatures](./signatures/) to understand input/output contracts
2. Move to [Modules](./modules/) to choose execution strategies and compose programs
3. Dive into [Module Runtime Context](./module-runtime-context/) to wire models, callbacks, and runtime safeguards
4. Understand the [Event System](./events/) so you can observe and hook into runtime behavior
5. Explore [Toolsets](./toolsets/) for typed agent capabilities
6. Study [Predictors](./predictors/) for different reasoning strategies
7. Learn about [CodeAct](./codeact/) for dynamic code generation (install the `dspy-code_act` gem)
8. Explore [Multimodal](./multimodal/) for text and image workflows
9. Study [Examples](./examples/) to see everything in action

Evaluation defines acceptable behavior. Optimizers use examples, metrics, and feedback to search supported program parameters.
