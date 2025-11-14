---
layout: blog
title: "Cut Prompt Tokens in Half with BAML + TOON"
date: 2025-11-07
description: "DSPy.rb now pairs BAML schemas with Sorbet::Toon payloads. The combo keeps Enhanced Prompting simple while saving ~9000 schema tokens and ~2400 data tokens per request."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/toon-data-format/"
image: /images/og/toon-data-format.png
reading_time: "4 min read"
---

**[DSPy Signatures](https://vicentereig.github.io/dspy.rb/getting-started/core-concepts/#signatures-as-the-contract)** anchor your app in a world where everything changes—prompting techniques, model families, even serialization formats. They’re the declarative contract for your prompt, so you never handcraft schemas or payloads again. JSON Schema and JSON payloads, however, bloat requests—especially when you’re shipping time-series data or long lists of structs that repeat every key. Starting today you can flip two symbols and keep Enhanced Prompting lean. Here’s the latest signature we used for the benchmark (now with nested structs and enums):

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
    const :subtasks, T::Array[Task], description: "Autonomously defined research subtasks"
    const :task_types, T::Array[TaskType], description: "Type classification for each task"
    const :priority_order, T::Array[Integer], description: "Priority rankings (1-5 scale)"
    const :estimated_effort, T::Array[EstimatedEffortWithReasoning], description: "Effort estimates in hours with rationale"
    const :dependencies, T::Array[Task], description: "Task dependency relationships"
    const :agent_requirements, T::Array[String], description: "Suggested agent skills"
  end
end
```

The remaining cost has always been **tokens**: JSON Schema is verbose and JSON payloads repeat every key. Starting today, you can flip two symbols and trim Enhanced Prompting back down to size—even for signatures that emit nested structs, enums, and rationales.

## TL;DR

- **Schema guidance:** switch `schema_format: :baml` and drop **3,528 → 608 characters** (≈ 83% smaller) even with nested structs/enums.
- **Data blocks:** switch `data_format: :toon` (Token-Oriented Object Notation, powered by the new `sorbet-toon` gem) and keep your inputs/outputs, ReAct histories, and tool payloads structured without JSON overhead. TOON itself lives at [github.com/toon-format/toon](https://github.com/toon-format/toon).
- **Net effect:** the enhanced `TaskDecomposition` signature now ships **≈ 9,490 fewer schema tokens** and **≈ 2,420 fewer data tokens** per Enhanced Prompting call. That still cuts prompts roughly in half, even though the tasks now carry objectives, success metrics, and reasoning.

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

That’s it. [Predictors](https://vicentereig.github.io/dspy.rb/getting-started/core-concepts/#predictors-basic-llm-operations), [ChainOfThought](https://vicentereig.github.io/dspy.rb/core-concepts/modules/#chain-of-thought), [ReAct](https://vicentereig.github.io/dspy.rb/blog/articles/react-agent-tutorial/), and every [DSPy module](https://vicentereig.github.io/dspy.rb/core-concepts/modules/) keep the same API; prompts just get cheaper.

## Why TOON + BAML matters

| Scenario | JSON Schema + JSON Data | BAML Schema + TOON Data |
|----------|------------------------|-------------------------|
| Signature guidance size | 3,528 chars | 608 chars |
| Sample input + output payload | 2,063 chars | 1,180 chars |
| Total prompt tokens (Enhanced Prompting) | ~13,500 | **~6,300** |

_Source: `examples/baml_vs_json_benchmark.rb`, live run `baml_benchmark_20251107_172759.json`._

That reduction isn’t just abstract token math:

- **Schema savings:** ~9,490 tokens disappear every time you render the signature guidance. That’s ~75% of the system prompt cost.
- **Payload savings:** TOON trims another ~2,420 tokens per request by avoiding repeated JSON keys.
- **Latency/cost:** When a model follows TOON, per-call cost falls 10‑20% and latency drops 15‑25% (e.g., `gpt-4o` BAML+TOON runs averaged 4.7 s vs 20 s for JSON+JSON in the benchmark). The same pattern held for Anthropic and Gemini models.

### What the model feels

- **Clear guidance, compact tables:** BAML renders the signature schema in a TypeScript-like form instead of a 200-line JSON Schema blob. Models latch onto the important parts faster.
- **Structured payloads without braces:** Sorbet::Toon turns your input struct into a Token-Oriented Object Notation (TOON) block. Arrays of structs become literal tables, so histories, toolsets, time-series data, and complex outputs stop repeating field names. JSON adds padding every time you send a list; TOON stays slim.
- **Enhanced Prompting by default:** You keep the exact same predictor APIs—no function calls or json schema extraction tricks. Swapping formats only changes how we render the prompt, not how you write or parse completions.

### Where the savings show up

1. **[Prediction prompts](/getting-started/core-concepts/#predictors-basic-llm-operations)** – any signature-backed `Predict` now emits TOON payloads, so even single-call apps get the 57% token cut.
2. **[ReAct loops](/blog/articles/react-agent-tutorial/)** – every turn now shares tools, histories, and observations as TOON. Long multi-tool dialogues stop reprinting JSON hashes.
3. **[Tool ecosystems](https://vicentereig.github.io/dspy.rb/core-concepts/toolsets/)** – TOON preserves typing (thanks to `Sorbet::Toon.decode`), so tool outputs round-trip back into Sorbet structs without manual serialization glue.

## FAQ

**Do I need to use BAML and TOON together?**
: No. They’re independent toggles. Use `schema_format: :baml` when you want compact schema guidance, `data_format: :toon` when you want lean payloads. You can enable either one (or both) per LM.

**Where’s the benchmarking code?**
: In [`examples/baml_vs_json_benchmark.rb`](https://github.com/vicentereig/dspy.rb/blob/feature/sorbet-toon-codec/examples/baml_vs_json_benchmark.rb). It ships with the repo and emits the same `.json/.csv/.txt` artifacts referenced here.

**Does this rely on function calling or structured outputs?**
: No. Everything stays in Enhanced Prompting—you still write plain `Predict`, `ChainOfThought`, or `ReAct` code and parse completions the same way.

**Can I combine TOON with provider-native structured outputs?**
: Not today. Provider structured outputs still expect JSON. TOON is purpose-built for Enhanced Prompting, so use it when you’re controlling the prompt yourself.

**Will TOON break my ReAct tools or custom modules?**
: No. ReAct, toolsets, and other DSPy modules already understand `data_format: :toon`; they simply serialize histories, tools, and responses using Sorbet::Toon instead of JSON.

**What’s the migration diff?**

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

Flip the formats, keep your prompts declarative, and run TOON wherever Enhanced Prompting makes sense.
