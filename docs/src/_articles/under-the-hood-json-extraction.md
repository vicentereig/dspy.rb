---
layout: blog
title: "Under the Hood: JSON Requests and Extraction in DSPy.rb"
date: 2025-03-09
description: "How DSPy.rb selects provider-native structured output, extracts JSON candidates, and constructs typed prediction values."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/under-the-hood-json-extraction/"
image: /images/og/under-the-hood-json-extraction.png
---

`DSPy::LM#chat` has one structured-response path. It builds messages from the module's prompt, lets `JSONStrategy` add provider-specific request parameters, sends the request through the adapter, extracts a JSON candidate, and parses the result. `DSPy::Predict` then constructs the prediction against the signature's output schema.

## Request Preparation

`JSONStrategy#prepare_request` identifies the adapter and may add native structured-output parameters.

### OpenAI and Compatible Adapters

For a supported OpenAI model with structured outputs enabled, DSPy.rb converts the signature to the OpenAI response format:

```ruby
request_params[:response_format] =
  DSPy::OpenAI::LM::SchemaConverter.to_openai_format(signature_class)
```

The adapter passes `response_format` to `chat.completions.create`. Ollama and OpenRouter use compatible request shapes, but their selected backend model may reject the parameter. Those adapters contain a narrow compatibility fallback that disables structured output and repeats that request without `response_format`.

### Gemini

For a supported Gemini model, the strategy adds:

```ruby
request_params[:generation_config] = {
  response_mime_type: "application/json",
  response_json_schema: schema
}
```

The Gemini adapter merges that hash into the request passed to `generate_content` or `stream_generate_content`.

### Anthropic

When Anthropic structured outputs are enabled, the strategy converts the signature and supplies Anthropic's structured-output request fields. On the current `main` implementation this uses the Anthropic beta structured-output API and its dated beta flag. That request shape is version-sensitive; the adapter owns it so modules do not have to.

### Prompt-Based Providers

If an adapter does not receive native schema parameters, the ordinary prompt includes the signature's input and output schemas and asks for the output fields in JSON. `schema_format: :baml` can make that guidance smaller. `data_format: :toon` selects a different prompt and parser path and therefore bypasses JSON structured output.

## Candidate Extraction

Every JSON response passes through the same content extractor. It tries, in order:

1. a fenced `json` block;
2. a generic fenced block;
3. the complete response;
4. an object embedded in surrounding text.

Each candidate must pass `JSON.parse`. Before that check, DSPy.rb applies two narrow repairs: it removes a comma immediately before the final object brace and escapes raw control characters inside quoted strings. If no candidate parses, the original content reaches `LM#parse_response`, which raises a parsing error with provider and model context in the debug log.

The embedded-object matcher is bounded, not a general JSON parser. It handles only limited nesting. Native structured output is preferable when the provider and model support it.

## Prediction Construction

Parsing yields a hash. The signature still has to turn that hash into application values. `DSPy::Prediction` converts scalar fields, enums, structs, arrays, nilable values, and supported unions against the output schema. The prediction includes both the original inputs and converted outputs.

This order matters:

```text
signature
  -> prompt and provider schema
  -> adapter request
  -> response content
  -> JSON candidate
  -> JSON.parse
  -> prediction conversion
```

A provider can return syntactically valid JSON that fails prediction conversion. A converted prediction can still be semantically wrong. Parsing, shape validation, and evaluation remain separate checks.

## Retry Boundaries

Current DSPy.rb core performs one prediction attempt. The retry-handler and multi-strategy fallback system from releases before v0.28.0 no longer exists. Provider SDKs may retry transport failures according to their own configuration. Applications should add domain retries only for failures they can classify and only when repeating the request is acceptable.

The useful abstraction is the signature, not a collection of provider prompt templates. The signature stays fixed while the adapter chooses the request shape and the prediction enforces the Ruby boundary.
