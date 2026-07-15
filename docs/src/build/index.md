---
layout: docs
title: "Build DSPy.rb Programs and Agents"
description: "Choose a DSPy.rb composition, retrieval, multimodal, Toolset, or stateful-agent guide."
date: 2026-07-15 00:00:00 +0000
---
# Build with DSPy.rb

Choose the smallest execution shape that owns the task. Use Ruby for known sequencing and branches; use a bounded agent when the model has a useful choice among reviewed tools.

## Compose a Program

- [Examples](/dspy.rb/core-concepts/examples/) defines typed inputs and expected outputs used by composition, evaluation, and optimization.
- [Pipelines](/dspy.rb/advanced/pipelines/) composes multiple inference stages with ordinary Ruby control flow.
- [RAG](/dspy.rb/advanced/rag/) combines retrieval with typed generation.
- [Multimodal Inputs](/dspy.rb/core-concepts/multimodal/) adds images to a typed signature.

## Build an Agent

- [Toolsets](/dspy.rb/core-concepts/toolsets/) groups reviewed Ruby operations for a bounded `ReAct` loop.
- [Stateful Agents](/dspy.rb/advanced/stateful-agents/) keeps conversation state in application-owned storage.

Before choosing an execution shape, learn [signatures, predictors, and modules](/dspy.rb/core-concepts/). After the program works, [evaluate its behavior](/dspy.rb/optimization/evaluation/).
