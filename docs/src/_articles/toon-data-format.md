---
layout: blog
title: "Compact Schemas and Payloads with BAML and TOON"
date: 2025-11-07
description: "Use BAML for compact schema guidance and TOON for compact structured payloads in DSPy.rb's prompt-based path."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/toon-data-format/"
image: /images/og/toon-data-format.png
reading_time: "4 min read"
---

[DSPy signatures](https://oss.vicente.services/dspy.rb/core-concepts/signatures/) describe inputs and outputs once. DSPy.rb can render that description in JSON Schema, BAML, or TOON-oriented guidance. It can also render prompt payloads as JSON or [Token-Oriented Object Notation](https://github.com/toon-format/toon).

Those are separate choices:

- `schema_format: :baml` changes how the signature appears in the system prompt.
- `data_format: :toon` changes how input and output values appear in the prompt and how DSPy.rb decodes the response.

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

## Where the Formats Apply

`data_format: :toon` selects DSPy.rb's prompt-based response path. Provider-native structured outputs expect JSON, so `DSPy::LM` does not request native structured output when the data format is TOON. The system prompt asks for a fenced TOON block; after the response arrives, `DSPy::Schema::SorbetToonAdapter` decodes it against the signature.

The predictor API does not change:

```ruby
predictor = DSPy::Predict.new(TaskDecomposition)
result = predictor.call(
  topic: "Build user authentication system",
  context: "Focus on security and Rails integration"
)
```

[Predict](https://oss.vicente.services/dspy.rb/core-concepts/predictors/), [ChainOfThought](https://oss.vicente.services/dspy.rb/core-concepts/predictors/#dspychainofthought), and [ReAct](https://oss.vicente.services/dspy.rb/blog/articles/react-agent-tutorial/) can carry the configured format through their prompts. ReAct also renders its history and observations through the configured data format.

## What the Benchmark Measured

The repository benchmark compared one nested `TaskDecomposition` signature and its sample payloads:

| Representation | Characters in benchmark artifact |
|---|---:|
| JSON Schema guidance | 3,528 |
| BAML schema guidance | 608 |
| JSON sample input and output | 2,063 |
| TOON sample input and output | 1,180 |

Source: [`examples/baml_vs_json_benchmark.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/baml_vs_json_benchmark.rb).

These character counts establish that the selected example is smaller. They do not establish a general latency percentage, cost reduction, or model-quality result. Tokenization varies by model, and a compact format helps only when the model follows it accurately.

## Choose Each Format Independently

Use BAML when JSON Schema guidance dominates a prompt and the prompt-based path is acceptable. Use TOON when payloads contain repeated records or nested structures that TOON represents compactly. Keep JSON when provider-native structured output is more valuable than prompt size, or when the model handles JSON more reliably.

The two settings are independent. Measure the complete request and evaluation result for the models you deploy.
