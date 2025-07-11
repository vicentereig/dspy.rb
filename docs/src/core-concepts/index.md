---
layout: docs
title: Core Concepts
description: Master the fundamental building blocks of DSPy.rb
---

# Core Concepts

Understanding DSPy.rb's core concepts is essential for building reliable LLM applications. This section covers the fundamental building blocks and how they work together.

## The Building Blocks

DSPy.rb is built on these main concepts:

### [Signatures](/core-concepts/signatures/)
Define what your LLM operations should do - the inputs and outputs. Think of them as type-safe contracts for AI operations.

### [Modules](/core-concepts/modules/)
Implement how to achieve what signatures define. Modules are composable units that can be combined to build complex workflows.

### [Memory](/core-concepts/memory/)
Store and retrieve information across interactions to build stateful agents that remember user preferences and context.

### [Toolsets](/core-concepts/toolsets/)
Group related tools in a single class for agent integration. Toolsets provide agents with capabilities like memory operations, file access, and API calls.

### [Predictors](/core-concepts/predictors/)
Connect your modules to language models with different strategies like chain-of-thought reasoning or tool use.

### [CodeAct](/core-concepts/codeact/)
Enable AI agents to dynamically write and execute Ruby code for creative problem-solving.

### [Examples](/core-concepts/examples/)
Learn from real-world use cases and patterns that demonstrate best practices for common scenarios.

## Start Learning

We recommend reading through these concepts in order:

1. Start with [Signatures](/core-concepts/signatures/) to understand input/output contracts
2. Move to [Modules](/core-concepts/modules/) to learn how to build workflows
3. Learn about [Memory](/core-concepts/memory/) for stateful agents
4. Explore [Toolsets](/core-concepts/toolsets/) for agent capabilities
5. Study [Predictors](/core-concepts/predictors/) for different reasoning strategies
6. Learn about [CodeAct](/core-concepts/codeact/) for dynamic code generation
7. Study [Examples](/core-concepts/examples/) to see everything in action

Each concept builds on the previous ones, creating a comprehensive framework for LLM development.