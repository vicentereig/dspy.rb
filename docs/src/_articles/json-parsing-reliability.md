---
layout: blog
title: "Reducing JSON Parsing Failures in DSPy.rb"
date: 2025-03-08
description: "How provider-native structured outputs, prompt-based JSON, extraction, and runtime validation fit together in DSPy.rb."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/json-parsing-reliability/"
image: /images/og/json-parsing-reliability.png
---

An LM can return valid prose and still break an application that expects JSON. DSPy.rb narrows that boundary in three stages: request a structured response when the provider supports it, extract a JSON candidate when it does not, then construct the signature's declared Ruby values.

Each stage catches a different failure. None guarantees that the answer is correct.

## Declare the Boundary

```ruby
class ProductInfo < DSPy::Signature
  description "Extract product information from text"

  input do
    const :text, String
  end

  output do
    const :name, String
    const :price, Float
    const :in_stock, T::Boolean
  end
end
```

The signature supplies the output schema. `DSPy::Predict` uses it to build the request and to convert the parsed response.

## Prefer Native Structured Output When Available

Provider adapters can translate the signature into provider-specific request fields:

- OpenAI-compatible adapters use `response_format` for models that DSPy.rb marks as supporting structured output.
- Gemini uses `generation_config` with `response_mime_type: "application/json"` and `response_json_schema` for supported models.
- Anthropic uses its structured-output request fields when `structured_outputs` is enabled.

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV.fetch('OPENAI_API_KEY'),
    structured_outputs: true
  )
end

extractor = DSPy::Predict.new(ProductInfo)
product = extractor.call(text: "The iPhone 15 Pro costs $999 and is available")
```

The option enables the adapter path; actual support still depends on the selected provider and model. OpenRouter and Ollama may retry a request without `response_format` when their OpenAI-compatible endpoint rejects that parameter.

## Prompt-Based JSON Remains Available

Set `structured_outputs: false` to keep the signature schema and output instructions in the prompt:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    'anthropic/claude-sonnet-4-20250514',
    api_key: ENV.fetch('ANTHROPIC_API_KEY'),
    structured_outputs: false
  )
end
```

For JSON responses, `JSONStrategy` checks a `json` fence, a generic code fence, the complete response, and an embedded object. It accepts a candidate only when `JSON.parse` succeeds. It also removes a trailing comma immediately before the final object brace and escapes raw control characters inside strings.

That normalization is deliberately narrow. DSPy.rb does not guess missing fields, rewrite arbitrary malformed JSON, or silently turn prose into application data.

## Validation Happens After Parsing

Valid JSON can still violate the signature. A missing field, unknown enum value, or incompatible nested object fails when DSPy.rb constructs the prediction. Conversely, a schema-valid response can still contain a bad classification or invented fact. Evaluate semantic behavior separately.

Current DSPy.rb core executes one prediction attempt. It does not include the automatic retry, fallback, or response cache described by older releases. Provider SDKs may have their own transport retry settings, and applications can add retry policy around failures they can classify safely.

Use native structured output when the selected model supports it. Use prompt-based JSON when portability or an alternate data format matters. In both cases, keep the signature as the boundary and test the failures the application needs to handle.
