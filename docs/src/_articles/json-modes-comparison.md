---
layout: blog
title: "JSON Mode Comparison: Prompted JSON and Structured Outputs"
date: 2025-09-18
description: "A dated benchmark of prompt-based JSON and provider-native structured outputs across eight models."
author: "Vicente Reig"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/json-modes-comparison/"
image: /images/og/json-modes-comparison.png
---

[DSPy.rb](https://github.com/vicentereig/dspy.rb) can obtain structured responses in two ways. The prompt-based path renders the signature schema and asks the model for JSON. The provider-native path translates the signature into the selected provider's structured-output request fields.

I ran both paths once across eight models in September and October 2025. The table records those requests, not a standing model recommendation. Provider APIs, prices, model aliases, and latency change. One request per cell also gives us no estimate of variance.

## The Two Request Paths

**Prompt-based JSON** includes schema guidance and output instructions in the messages. It works when an adapter has no native schema path or when `structured_outputs: false` is selected. DSPy.rb still extracts and parses the returned JSON.

**Provider-native structured output** sends the converted signature through provider-specific fields. Current adapters use OpenAI-compatible `response_format`, Gemini `generation_config`, and Anthropic structured-output parameters. Support depends on the provider and model.

Both paths end at the same runtime boundary: parse the response and convert its fields against the signature.

## Recorded Results

All 16 recorded calls returned a result accepted by the benchmark. That means a 100% observed success rate for this small run, not a 100% reliability claim.

| Provider | Model | Prompt-based JSON | Native structured output |
|---|---|---:|---:|
| OpenAI | gpt-4o | 2.302s / $0.002833 | 1.769s / $0.001658 |
| OpenAI | gpt-4o-mini | 2.944s / $0.000169 | 2.111s / $0.000097 |
| OpenAI | gpt-5 | 16.005s / $0.011895 | 22.921s / $0.015065 |
| OpenAI | gpt-5-mini | 8.303s / $0.001361 | 10.694s / $0.001881 |
| Anthropic | claude-sonnet-4-5 | 3.411s / $0.004581 | 3.401s / $0.005886 |
| Anthropic | claude-opus-4-1 | 4.993s / $0.022380 | 4.796s / $0.025335 |
| Google | gemini-2.5-pro | 10.478s / $0.001623 | 6.787s / $0.001023 |
| Google | gemini-2.5-flash | 15.704s / $0.000096 | 7.943s / $0.000050 |

Source: [`examples/json_modes_benchmark.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb). The repository script remains useful for rerunning the comparison, but the historical output file linked by the original article is no longer present on `main`.

The recorded run favored native output for GPT-4o and Gemini, prompt-based JSON for the two GPT-5 variants, and showed similar latency with different token costs for the Anthropic models. Model behavior, generated token counts, provider implementation, and ordinary request variance can all affect those differences. This run cannot separate them.

## Running the Same Program Both Ways

```ruby
class ActionType < T::Enum
  enums do
    Create = new('create')
    Update = new('update')
    Delete = new('delete')
  end
end

class TodoAction < T::Struct
  const :action_type, ActionType
  const :task, String
  const :priority, String, default: 'medium'
end

class TodoListManagement < DSPy::Signature
  description "Parse a request into todo actions"

  input do
    const :user_request, String
  end

  output do
    const :actions, T::Array[TodoAction]
    const :summary, String
  end
end
```

Enable native structured output when the adapter and model support it:

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV.fetch('OPENAI_API_KEY'),
    structured_outputs: true
  )
end
```

Set `structured_outputs: false` to benchmark the prompt-based JSON path with the same signature and call:

```ruby
predictor = DSPy::Predict.new(TodoListManagement)
result = predictor.call(
  user_request: "Add groceries and schedule Friday's team meeting"
)
```

## Choosing a Path

Start with native structured output when the selected provider and model support the required schema. It removes some format-following work from the prompt. Keep prompt-based JSON for unsupported models, portable experiments, or compact schema and data formats such as BAML and TOON.

Then rerun the benchmark with several repetitions, realistic signatures, current prices, and a task metric. Latency and token cost matter only alongside accepted output quality.

## Related Articles

- [Typed Values in DSPy.rb Predictions](https://oss.vicente.services/dspy.rb/blog/articles/type-safe-prediction-objects/)
- [Under the Hood: JSON Requests and Extraction](https://oss.vicente.services/dspy.rb/blog/articles/under-the-hood-json-extraction/)
- [Reducing JSON Parsing Failures](https://oss.vicente.services/dspy.rb/blog/articles/json-parsing-reliability/)
