---
layout: docs
title: "DSPy.rb and LangChain Ruby: Programming Model Comparison"
name: DSPy.rb vs LangChain
description: "Compare DSPy.rb's typed, optimizable programs with LangChain Ruby's integration-oriented component model."
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: Framework Comparison
  url: "/advanced/dspy-vs-langchain/"
date: 2025-09-18 00:00:00 +0000
---

# DSPy.rb and LangChain Ruby

The libraries overlap, but they organize application code differently. DSPy.rb starts with typed task contracts, modules, evaluation, and optimization. LangChain Ruby emphasizes provider clients, prompt templates, retrieval integrations, and prebuilt components.

Both projects change quickly. Verify integration availability and API syntax in each project's current documentation before choosing between them.

## DSPy.rb Model

Define the task once, then choose an execution module:

```ruby
class QuestionAnswering < DSPy::Signature
  input do
    const :question, String
    const :context, String
  end

  output do
    const :answer, String
  end
end

qa = DSPy::Predict.new(QuestionAnswering)
result = qa.call(question: question, context: context)
```

The signature supplies the typed boundary. `Predict`, `ChainOfThought`, and `ReAct` provide different execution strategies. Ruby control flow composes modules into fixed pipelines; ReAct gives the model a bounded tool-selection loop.

Evaluation and optimizers operate on the resulting program. They do not remove the need for examples, metrics, budgets, or deployment policy.

## LangChain Ruby Model

LangChain Ruby is useful when an application benefits from its provider, retrieval, loader, or tool integrations. Its APIs and available components are maintained by that project, so use its current documentation for executable examples.

## Choose by the Boundary You Need

Choose DSPy.rb when:

- A typed input and output contract should define the task.
- You want to compare execution modules without rewriting the task interface.
- Evaluation and instruction or demonstration optimization are part of the development loop.
- Ruby should own deterministic orchestration around model calls.
- A tool-using agent needs typed tools and an iteration bound.

Consider LangChain Ruby when its maintained integrations remove application work you would otherwise own, especially around retrieval and document ingestion.

The choice is not a general claim about speed, memory, or quality. Provider latency dominates many workloads, and prompt or token differences depend on the exact program. Benchmark the task with the same model, data, metric, and concurrency.

## Migration to DSPy.rb

1. Capture representative inputs and expected behavior before changing the implementation.
2. Express the task as a signature.
3. Start with `DSPy::Predict`; add reasoning or tools only when the task requires them.
4. Keep retrieval, persistence, permissions, and side effects in application-owned components.
5. Evaluate the old and new paths on the same examples.
6. Optimize only after the metric reflects the behavior you intend to ship.

See [RAG](/advanced/rag/) for application-owned retrieval, [Pipelines](/advanced/pipelines/) for fixed composition, and [Program Optimization](/optimization/prompt-optimization/) for evaluation-driven compilation.
