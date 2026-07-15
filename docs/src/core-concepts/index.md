---
layout: docs
title: "DSPy.rb Core Concepts: Signatures, Modules, and Predictors"
description: "Learn how signatures, modules, Ruby programs, agents, tools, evaluation, and optimization fit together in DSPy.rb."
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-13 00:00:00 +0000
---
# Core Concepts

Start with a signature, choose a predictor, then wrap calls in a module when the program needs reusable Ruby composition. Use `ReAct` later, when the model should choose among typed tools.

## The Programming Model

### [Signatures](./signatures/)
Define what your LLM operations should do - the inputs and outputs. Think of them as type-safe contracts for AI operations.

### [Predictors](./predictors/)
Execute a signature with `Predict`, `ChainOfThought`, or a bounded `ReAct` tool loop.

### [Modules](./modules/)
Encapsulate predictor calls and compose them with ordinary Ruby control flow.

### Application State
Keep conversation history, user preferences, checkpoints, and other durable state in application-owned storage. Pass the state a module needs through typed inputs.

Once those three abstractions are clear, use the [Build selector](/dspy.rb/build/) for examples, pipelines, retrieval, multimodal inputs, Toolsets, and stateful agents. Runtime context, events, interception, Rails, storage, observability, and troubleshooting live under [Operate](/dspy.rb/production/).

## Start Learning

We recommend reading through these concepts in order:

1. Define an input/output contract with [Signatures](./signatures/).
2. Execute it with [Predictors](./predictors/).
3. Encapsulate and compose calls with [Modules](./modules/).
4. Continue to [Examples](/dspy.rb/core-concepts/examples/) and [Toolsets](/dspy.rb/core-concepts/toolsets/) when you are ready to build.

Evaluation defines acceptable behavior. Optimizers use examples, metrics, and feedback to search supported program parameters.
