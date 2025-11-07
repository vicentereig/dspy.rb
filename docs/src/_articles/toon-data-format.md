---
layout: blog
title: "TOON Everywhere: Schemas, Payloads, and Token Diets"
date: 2025-11-07
description: "Sorbet::Toon brings TOON data blocks to DSPy.rb. Pair it with BAML schemas and Enhanced Prompting to cut request tokens in half without touching your model."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/toon-data-format/"
image: /images/og/toon-data-format.png
---

A month ago we proved that swapping JSON Schema for BAML removed ~80% of the boilerplate in Enhanced Prompting. Today Sorbet::Toon ships the missing half: compact TOON payloads for your inputs/outputs, ReAct histories, and tool wiring. Together they keep prompts readable while shaving hundreds of tokens off every call—no function-calling, no JSON parsing band–aids.

## Sorbet::Toon in two lines

Add the gem (already listed in `dspy.gemspec`) and let the auto-loader enable struct/enum helpers:

```ruby
gem 'sorbet-toon'
require 'sorbet/toon'   # auto-calls Sorbet::Toon.enable_extensions!
```

Then tell DSPy to keep Enhanced Prompting but emit TOON payloads:

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY'],
    schema_format: :baml,   # compact guidance tables
    data_format: :toon      # TOON user/output blocks everywhere
  )
end
```

That single `data_format: :toon` switch flows through:

- **Predict / ChainOfThought / ReAct** prompts (`Prompt#render_user_prompt` now injects TOON blocks when the signature is present).
- **ReAct history + tools**: we serialize tool descriptors, per-step action inputs, and observations as TOON, so ReAct loops stay structured even before the LM answers.
- **DSPy::LM parsing**: `Sorbet::Toon.decode` reconstructs Sorbet structs, enums, and typed arrays without touching JSON.

## Benchmarking schema + data formats

`examples/baml_vs_json_benchmark.rb` now sweeps every combination of schema format (JSON vs BAML) and data format (JSON vs TOON) while staying in Enhanced Prompting mode. You can run it offline (no API keys required) to inspect raw prompt sizes:

```bash
BAML_BENCHMARK_LIVE=0 bundle exec ruby examples/baml_vs_json_benchmark.rb
```

The latest run (files `schema_data_benchmark_20251107_013851.{json,csv}`) used the rich `TaskDecomposition` signature and the exact input we ship in the docs. We measure total characters of the rendered system+user messages and convert to tokens with the same 4-char heuristic we use elsewhere.

### Schema vs data payload sizes

| Component | JSON | Alt Format | % Savings |
|-----------|------|------------|-----------|
| Schema guidance (input + output) | 1,953 chars | 351 chars (BAML) | **82.0%** |
| Sample user payload | 221 chars | 167 chars (TOON) | **24.4%** |

BAML keeps the signature readable (table form, no `$schema` boilerplate). TOON trims the long JSON block that previously duplicated every field name.

### Prompt-level token impact (Enhanced Prompting)

| Schema Format | Data Format | Estimated Tokens | Δ vs JSON/JSON |
|---------------|-------------|------------------|----------------|
| JSON Schema   | JSON Data   | 699              | — |
| JSON Schema   | TOON Data   | 705              | +6 (code fence overhead) |
| BAML Schema   | JSON Data   | 297              | **−402 (−57.5%)** |
| BAML Schema   | TOON Data   | 303              | **−396 (−56.6%)** |

The big win still comes from BAML schemas—TOON payloads are a nice 6-token cherry on top once you also want your ReAct loops, tool inputs, and observation streams to stay typed end-to-end.

> 📦 Need the raw numbers? Crack open `schema_data_comparison_20251107_013851.txt` for the same table plus the exact prompt bodies.

## Where Sorbet::Toon plugs in

1. **Prompt rendering** – `Sorbet::Toon::SignatureFormatter` mirrors signature order, optional elision, and table formatting so models see a deterministic spec whether you pick JSON Schema or BAML.
2. **Adapters** – `DSPy::Schema::SorbetToonAdapter` handles TOON code fences, logging, and conversion back into structs/enums with default propagation.
3. **Agents & tools** – ReAct now feeds TOON everywhere (available tools array, history entries, observation processors) so downstream reasoning never pays the JSON tax.

All of this runs in the default Enhanced Prompting stack—no function-calling, no streaming delta gymnastics. Flip two symbols, keep your existing few-shot examples, and enjoy a 57% prompt reduction before the model even thinks.

Ready to adopt it?

```ruby
predictor = DSPy::Predict.new(TaskDecomposition)
result = predictor.call(
  topic: "Sustainable technology adoption in developing countries",
  context: "Focus on practical implementation challenges and success stories",
  complexity_level: ComplexityLevel::Intermediate
)

puts Sorbet::Toon.encode(result.to_h, signature: TaskDecomposition, role: :output)
```

The output lands in TOON, your logs stay structured, and token budgets stop melting. Sorbet::Toon is part of DSPy.rb now—run the benchmark, swap the formats, and ship lean prompts.
