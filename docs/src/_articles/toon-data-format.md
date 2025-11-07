---
layout: blog
title: "Cut Prompt Tokens in Half with BAML + TOON"
date: 2025-11-07
description: "DSPy.rb now pairs BAML schemas with Sorbet::Toon payloads. The combo keeps Enhanced Prompting simple while saving ~400 tokens per request."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/toon-data-format/"
image: /images/og/toon-data-format.png
---

**[DSPy Signatures](https://vicentereig.github.io/dspy.rb/getting-started/core-concepts/#signatures-as-the-contract)** anchor your app in a world where everything changes—prompting techniques, model families, even serialization formats. They’re the declarative contract for your prompt, so you never handcraft schemas or payloads again. JSON Schema and JSON payloads, however, bloat requests—especially when you’re shipping time-series data or long lists of structs that repeat every key. Starting today you can flip two symbols and keep Enhanced Prompting lean. Here’s the exact signature we used for the benchmark:

```ruby
class TaskDecomposition < DSPy::Signature
  description "Autonomously analyze a research topic and define optimal subtasks with strategic prioritization"

  input do
    const :topic, String, description: "The main research topic to investigate"
    const :context, String, description: "Any additional context or constraints"
    const :complexity_level, ComplexityLevel,
      description: "Desired complexity level for task decomposition"
  end

  output do
    const :subtasks, T::Array[String], description: "Autonomously defined research subtasks"
    const :task_types, T::Array[String], description: "Type classification for each task"
    const :priority_order, T::Array[Integer], description: "Priority rankings (1-5 scale)"
    const :estimated_effort, T::Array[Integer], description: "Effort estimates in hours"
    const :dependencies, T::Array[String], description: "Task dependency relationships"
    const :agent_requirements, T::Array[String], description: "Suggested agent skills"
  end
end
```

The remaining cost has always been **tokens**: JSON Schema is verbose and JSON payloads repeat every key. Starting today, you can flip two symbols and trim Enhanced Prompting back down to size.

## TL;DR

- **Schema guidance:** switch `schema_format: :baml` and drop 1,953 → 351 characters (≈ 82% smaller). Same signature, same Enhanced Prompting flow.
- **Data blocks:** switch `data_format: :toon` (powered by the new `sorbet-toon` gem) and keep your inputs/outputs, ReAct histories, and tool payloads structured without JSON overhead.
- **Net effect:** the rich `TaskDecomposition` signature now sends **303 tokens** instead of **699** in Enhanced Prompting. That’s a **≈ 57% reduction** per call without touching your model, few-shot examples, or tool code.

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY'],
    schema_format: :baml,
    data_format: :toon
  )
end
```

That’s it. Predictors, ChainOfThought, ReAct, and every DSPy module keep the same API; prompts just get cheaper.

## Why TOON + BAML matters

| Scenario | JSON Schema + JSON Data | BAML Schema + TOON Data |
|----------|------------------------|-------------------------|
| Signature guidance size | 1,953 chars | 351 chars |
| Sample input payload | 221 chars | 167 chars |
| Total prompt tokens (Enhanced Prompting) | 699 | **303** |

_Source: `examples/baml_vs_json_benchmark.rb`, offline run `schema_data_benchmark_20251107_013851.json`._

### What the model feels

- **Clear guidance, compact tables:** BAML renders the signature schema in a TypeScript-like form instead of a 200-line JSON Schema blob. Models latch onto the important parts faster.
- **Structured payloads without braces:** Sorbet::Toon turns your input struct into a TOON block. Arrays of structs become literal tables, so histories, toolsets, time-series data, and complex outputs stop repeating field names. JSON adds padding every time you send a list; TOON stays slim.
- **Enhanced Prompting by default:** You keep the exact same predictor APIs—no function calls or json schema extraction tricks. Swapping formats only changes how we render the prompt, not how you write or parse completions.

### Where the savings show up

1. **[Prediction prompts](/getting-started/core-concepts/#predictors-basic-llm-operations)** – any signature-backed `Predict` now emits TOON payloads, so even single-call apps get the 57% token cut.
2. **[ReAct loops](/blog/articles/react-agent-tutorial/)** – every turn now shares tools, histories, and observations as TOON. Long multi-tool dialogues stop reprinting JSON hashes.
3. **[Tool ecosystems](https://vicentereig.github.io/dspy.rb/core-concepts/toolsets/)** – TOON preserves typing (thanks to `Sorbet::Toon.decode`), so tool outputs round-trip back into Sorbet structs with zero DTO glue.

## What you need to do

1. Update to the latest DSPy.rb (Sorbet::Toon rides along as a dependency).
2. Flip `schema_format: :baml` and `data_format: :toon` in your `DSPy.configure` block or per-LM overrides.
3. When you want to inspect the raw numbers, peek at [`examples/baml_vs_json_benchmark.rb`](https://github.com/vicentereig/dspy.rb/blob/feature/sorbet-toon-codec/examples/baml_vs_json_benchmark.rb); it ships with the repo so you can repeat the comparison in your own environment.

Here’s the only code change most apps need:

```diff
 DSPy.configure do |c|
-  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
+  c.lm = DSPy::LM.new(
+    'openai/gpt-4o-mini',
+    api_key: ENV['OPENAI_API_KEY'],
+    schema_format: :baml,
+    data_format: :toon
+  )
 end
```

No new APIs, no migration slog—just leaner prompts that unlock more iterations per dollar. Flip the formats, keep your prompts declarative, and ship TOON-powered Enhanced Prompting everywhere.
