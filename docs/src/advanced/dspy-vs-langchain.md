---
layout: docs
title: "DSPy.rb and LangChain Ruby: Programming Model Comparison"
name: DSPy.rb vs LangChain
description: "Compare DSPy.rb's typed, optimizable programs with LangChain Ruby's integration-oriented component model."
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

LangChain Ruby starts closer to provider and integration primitives. Its current API includes a common LLM interface, prompt templates, structured-output parsers, vector-store clients, document loaders, tools, and a conversational `Assistant`.

The same question-answering task can be assembled from a prompt template and an LLM client:

```ruby
llm = Langchain::LLM::OpenAI.new(
  api_key: ENV.fetch("OPENAI_API_KEY")
)

prompt = Langchain::Prompt::PromptTemplate.new(
  template: "Answer from the context.\nContext: {context}\nQuestion: {question}",
  input_variables: ["context", "question"]
)

response = llm.chat(
  messages: [{
    role: "user",
    content: prompt.format(context: context, question: question)
  }]
)

answer = response.chat_completion
```

This API leaves the prompt and response shape explicit. For structured data, LangChain Ruby provides `StructuredOutputParser`, which accepts a JSON Schema, adds format instructions to a prompt, and parses the response. `OutputFixingParser` can ask the model to repair a parsing failure. Its `Assistant` manages conversation messages and automatic or manual tool execution, while its vector-search clients cover ingestion and retrieval for several databases.

See the project-maintained [LangChain Ruby README](https://github.com/patterns-ai-core/langchainrb#readme) and [API documentation](https://rubydoc.info/gems/langchainrb) for current provider and integration details.

## Equivalent Concepts, Different Centers

| Concern | DSPy.rb | LangChain Ruby |
|---|---|---|
| Task definition | Sorbet-backed signature with typed inputs and outputs | Prompt template, messages, and optional output parser |
| Model access | Provider adapters behind `DSPy::LM` | Provider clients behind `Langchain::LLM` |
| Structured results | Signature-derived schema and prediction coercion | JSON Schema supplied to `StructuredOutputParser` |
| Tool use | `DSPy::ReAct` with typed Ruby tools and an iteration limit | `Langchain::Assistant` with tool definitions and conversation state |
| Retrieval | Application-owned retrieval passed into modules | Vector-store clients, loaders, chunkers, and RAG helpers |
| Evaluation | Program evaluation with application metrics | RAGAS evaluation for retrieval-augmented answers |
| Optimization | Instructions and demonstrations compiled from examples and metrics | Prompt templates remain application-authored |

These rows describe the projects' documented APIs, not feature parity. A custom Ruby application can build any of these boundaries around either library.

## Choose by the Boundary You Need

Choose DSPy.rb when:

- A typed input and output contract should define the task.
- You want to compare execution modules without rewriting the task interface.
- Evaluation and instruction or demonstration optimization are part of the development loop.
- Ruby should own deterministic orchestration around model calls.
- A tool-using agent needs typed tools and an iteration bound.

Choose LangChain Ruby when its provider interface, prompt and parser objects, conversational assistant, or retrieval integrations match the application you need to assemble.

The choice is not a general claim about speed, memory, or quality. Provider latency dominates many workloads, and prompt or token differences depend on the exact program. Benchmark the task with the same model, data, metric, and concurrency.

## Migration to DSPy.rb

1. Capture representative inputs and expected behavior before changing the implementation.
2. Express the task as a signature.
3. Start with `DSPy::Predict`; add reasoning or tools only when the task requires them.
4. Keep retrieval, persistence, permissions, and side effects in application-owned components.
5. Evaluate the old and new paths on the same examples.
6. Optimize only after the metric reflects the behavior you intend to ship.

See [RAG](/dspy.rb/advanced/rag/) for application-owned retrieval, [Pipelines](/dspy.rb/advanced/pipelines/) for fixed composition, and [Program Optimization](/dspy.rb/optimization/prompt-optimization/) for evaluation-driven compilation.
