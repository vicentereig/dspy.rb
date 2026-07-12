---
layout: blog
order: 9
title: "Raw Chat API for Benchmarking and Migration"
date: 2025-07-23
description: "Use DSPy.rb's raw_chat API for direct provider conversations, instrumentation, and staged migration to typed modules."
tags: [api, benchmarking, migration, observability]
excerpt: |
  The raw_chat API sends message histories through a DSPy.rb adapter without signature parsing.
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/raw-chat-api/"
image: /images/og/raw-chat-api.png
---

`DSPy::LM#raw_chat` sends a message history through a provider adapter without building a signature prompt or parsing a typed prediction. It is useful when you already have a working prompt, need provider metadata, or want a baseline before moving behavior into DSPy modules.

## Array Form

```ruby
lm = DSPy::LM.new(
  "openai/gpt-4o-mini",
  api_key: ENV.fetch("OPENAI_API_KEY")
)

response = lm.raw_chat([
  { role: "system", content: "Answer as a Ruby maintainer." },
  { role: "user", content: "When should I use Fiber-local state?" }
])

puts response.content
pp response.usage&.to_h
pp response.metadata.to_h
```

The return value is `DSPy::LM::Response`. It contains the accumulated text, optional normalized usage, and provider-specific metadata.

Messages accept `system`, `user`, and `assistant` roles. DSPy.rb normalizes the hashes into `DSPy::LM::Message` objects and validates the role and content before calling the adapter.

## Builder Form

When `raw_chat` receives no message array, its block builds the history:

```ruby
response = lm.raw_chat do |messages|
  messages.system("Answer as a Ruby maintainer.")
  messages.user("When should I use Fiber-local state?")
end
```

The builder supports `system`, `user`, `assistant`, `user_with_image`, `user_with_images`, and `user_with_document`. Methods return the builder, so message construction can be chained.

The block has a different meaning in array form: it receives streaming callbacks from adapters that implement them. Do not combine the builder form with a streaming callback.

## Streaming Callbacks

```ruby
response = lm.raw_chat([
  { role: "user", content: "Explain Ruby fibers." }
]) do |chunk|
  handle_provider_chunk(chunk)
end
```

Callback values are currently provider-specific. Gemini yields Gemini chunks; other adapters may expose a different object or text fragment. The final `response.content` contains the accumulated text.

Raw streaming does not create partial typed DSPy predictions. `Predict` and other signature-based modules validate structured output after the complete response arrives.

## Multimodal Messages

```ruby
image = DSPy::Image.new(
  data: File.binread("architecture.png").bytes,
  content_type: "image/png"
)

response = lm.raw_chat do |messages|
  messages.user_with_image("Describe the request path.", image)
end
```

Provider media support differs. OpenAI accepts supported URLs or inline data; Anthropic and Gemini require inline image data in the current adapters. PDF documents are limited to the providers documented by `DSPy::Document` support.

## Use It as a Baseline

Suppose an application already maintains a long prompt string. Run that implementation through `raw_chat`, preserve the same evaluation examples, then build a signature-based version:

```ruby
baseline = lm.raw_chat([
  { role: "system", content: legacy_instructions },
  { role: "user", content: input }
])

candidate = DSPy.with_lm(lm) do
  DSPy::Predict.new(ChangelogSignature).call(changes: input)
end
```

Compare behavior with a metric that reflects the task. Token counts and latency are useful operational measurements, but neither establishes output quality.

Move to a module when you need typed fields, reusable composition, tool use, evaluation, or optimization. Keep `raw_chat` when the provider conversation itself is the API you need.

## Execution Boundary

`raw_chat` uses the same LM instrumentation path as other adapter calls. It does not run `JSONStrategy`, signature coercion, or prediction validation. Provider errors still pass through the adapter's error mapping, and transport retry behavior remains provider-SDK-specific.

That boundary is the point of the method: direct chat without opting out of DSPy.rb's provider and observability infrastructure.
