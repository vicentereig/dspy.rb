---
layout: docs
title: Advanced Topics
description: Explore advanced patterns and techniques in DSPy.rb
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-07-11 00:00:00 +0000
---
# Advanced Topics

These guides cover composition, agents, tools, retrieval, Rails integration, rich types, and evaluation. Use them after you can define a signature and run a module.

## Advanced Guides

### [DSPy.rb vs LangChain Ruby Comparison](./dspy-vs-langchain/)
Compare the two libraries' programming models and migration tradeoffs. Treat the historical benchmarks as context, not universal results.

### [Stateful Agents](./stateful-agents/)
Keep conversation state in application storage and pass the relevant context into a bounded agent loop.

### [Custom Toolsets](./custom-toolsets/)
Group typed database, file, and API operations for use by ReAct agents.

### [Pipelines](./pipelines/)
Compose modules with ordinary Ruby control flow when the application should determine the step order.

### [RAG (Retrieval-Augmented Generation)](./rag/)
Implement retrieval-augmented generation patterns to ground your LLM responses in real data.

### [Rich Types](./complex-types/)
Work with structured data, nested objects, and rich type hierarchies in your signatures.

### [Rails Integration](./rails-integration/)
Integrate DSPy.rb with Rails service objects, jobs, caching, enums, and instrumentation.

### [Custom Metrics](./custom-metrics/)
Define metrics that express acceptable behavior for evaluation and optimization.

Choose the smallest execution strategy that fits the task. Use a predictor for one typed call, Ruby control flow for fixed composition, and an agent when the model has a useful choice among tools or actions.
