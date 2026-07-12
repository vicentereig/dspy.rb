---
layout: blog
title: "Using Google Gemini with DSPy.rb"
description: "Configure the Gemini adapter, define typed predictions, pass inline images, and inspect provider metadata."
date: 2025-08-26
author: "Vicente Reig"
category: "Features"
reading_time: "4 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/introducing-google-gemini-support/"
---

A project outgrows you the moment the first contributor merges to `main`. Stefan Froelich added DSPy.rb's Gemini adapter in v0.20.0, including text generation, inline images, usage metadata, streaming transport, and structured responses.

This guide describes the adapter that exists now. Model availability and limits belong to Google's documentation and can change independently of DSPy.rb.

## Install and Configure

Add the core and Gemini adapter gems:

```ruby
gem "dspy"
gem "dspy-gemini"
```

Set `GEMINI_API_KEY`, then configure a model using the `gemini/` provider prefix:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    "gemini/gemini-2.5-flash",
    api_key: ENV.fetch("GEMINI_API_KEY")
  )
end
```

DSPy.rb passes the model name to the Gemini client. Choose a model currently available to your Google AI account.

## Typed Prediction

A signature defines the input and the result your Ruby code expects. The adapter constructs the provider request; `Predict` coerces and validates the returned fields.

```ruby
class ContentAnalysis < DSPy::Signature
  input do
    const :content, String, description: "Text to analyze"
  end

  output do
    const :summary, String, description: "A concise summary"
    const :topics, T::Array[String], description: "Main topics in the text"
    const :confidence, Float, description: "Confidence from 0.0 to 1.0"
  end
end

analysis = DSPy::Predict.new(ContentAnalysis).call(content: article)

puts analysis.summary
puts analysis.topics.inspect
```

Typed output validation catches missing or incompatible fields. It does not establish that a summary is accurate or that a confidence value is calibrated; those are evaluation questions.

## Images

Gemini accepts inline image data through `DSPy::Image`. The current adapter supports JPEG, PNG, GIF, and WebP data up to DSPy.rb's 5 MB input limit. It does not fetch image URLs.

```ruby
class InspectImage < DSPy::Signature
  input do
    const :question, String
    const :image, DSPy::Image
  end

  output do
    const :answer, String
  end
end

image = DSPy::Image.new(
  data: File.binread("diagram.png").bytes,
  content_type: "image/png"
)

result = DSPy::Predict.new(InspectImage).call(
  question: "Which component owns retries?",
  image: image
)
```

For several images, use an array in the signature:

```ruby
class CompareImages < DSPy::Signature
  input { const :images, T::Array[DSPy::Image] }
  output { const :differences, T::Array[String] }
end
```

Whether a particular Gemini model accepts the media type and count remains a provider constraint.

## Structured Outputs

Gemini's adapter can use provider-native structured output when initialized with `structured_outputs: true`:

```ruby
lm = DSPy::LM.new(
  "gemini/gemini-2.5-flash",
  api_key: ENV.fetch("GEMINI_API_KEY"),
  structured_outputs: true
)

predictor = DSPy::Predict.new(ContentAnalysis)

result = DSPy.with_lm(lm) do
  predictor.call(content: article)
end
```

The schema converter supports the subset covered by DSPy.rb's Gemini specs, including nested structs, enums, arrays, nilable fields, and unions. Provider schema support can be narrower than Sorbet's type system. Test the signatures you deploy.

## Raw Responses and Streaming

`raw_chat` returns a `DSPy::LM::Response` with `content`, optional `usage`, and Gemini metadata:

```ruby
lm = DSPy::LM.new(
  "gemini/gemini-2.5-flash",
  api_key: ENV.fetch("GEMINI_API_KEY")
)

response = lm.raw_chat([
  { role: "user", content: "Explain Fiber-local storage in two sentences." }
])

puts response.content
pp response.usage&.to_h
pp response.metadata.to_h
```

The Gemini transport streams by default outside ordinary VCR recordings. When a block is supplied in array mode, the adapter yields provider chunks and still accumulates the final response:

```ruby
response = lm.raw_chat([{ role: "user", content: "Count to five." }]) do |chunk|
  pp chunk
end
```

Those callbacks expose provider chunks, not partial typed predictions. DSPy.rb validates a signature result after the complete response arrives.

## Provider Boundaries

- Gemini has no separate system role in this adapter; system messages are sent as user content.
- Inline image data is supported; image URLs are not.
- Safety ratings and finish reasons are exposed as metadata when Gemini returns them.
- Generation options accepted by `DSPy::LM.new` are passed to the adapter constructor only if that constructor declares them. The current Gemini constructor exposes `structured_outputs`, not a general generation-parameter API.

Keep the task in the signature, keep model-specific behavior at the adapter boundary, and evaluate the complete program against examples that resemble its actual inputs.
