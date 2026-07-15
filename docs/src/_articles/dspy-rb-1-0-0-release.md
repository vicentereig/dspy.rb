---
layout: blog
title: "DSPy.rb 1.0.0"
description: "DSPy.rb 1.0.0 follows revisions that added TOON/BAML, RubyLLM, Anthropic structured outputs, Langfuse tracing, JSON coercion changes, and multimodal document support."
date: 2026-04-11
author: "Vicente Reig"
category: "Release"
reading_time: "4 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/dspy-rb-1-0-0-release/"
image: /images/og/dspy-rb-1-0-0-release.png
---

DSPy.rb 1.0.0 is out. If you've been on the `0.3x` releases, `1.0.0` should feel familiar. This release marks the `1.x` line as the stable API rather than introducing a new programming model.

The release follows months of smaller revisions to provider, parsing, type, and observability boundaries.

## What Changed on the Way to 1.0

The preceding releases added:

- TOON and BAML formats for prompt-rendered schemas and data;
- a RubyLLM adapter for models and providers available through RubyLLM;
- Anthropic strict mode and Beta structured-output support;
- Langfuse tracing and score reporting;
- additional type-coercion and JSON-extraction failure handling; and
- multimodal document inputs for supported providers.

Each feature has its own provider, model, SDK, or application boundary; the `1.x` label does not make those capabilities uniform.

## What Lands in 1.0.0 Itself

The `1.0.0` release itself includes a smaller set of changes than the full road to 1.0:

- Anthropic PDF document support through `DSPy::Document`, `raw_chat`, and `Predict`
- GEPA evaluation runs that continue when an individual example fails
- safer sanitization for control characters in extracted JSON
- updated adapter SDK floors, with compatibility expressed through dependencies instead of runtime guardrails

The dependency floors make compatibility explicit at installation time instead of relying on runtime version checks.

## Why 1.0 Now

For users of the later `0.3x` releases, `1.0.0` preserves the existing programming model. The `1.x` designation marks the current API as the supported stable surface.

## Thank You

Thanks to everyone who has contributed to DSPy.rb over the life of the project:

- TheDumbTechGuy
- Francois Buys
- Benjamin Jackson
- Kieran Klaassen
- Oleksiy Kovyrin
- Thomas Klemm
- tleish
- Abdelrahman Alzboon
- Lior Brauer
- Avi Flombaum

Open source is still a bizarre system. People with fully separate lives voluntarily improve a library for strangers on the internet. That is generous, slightly irrational, and deeply appreciated.

## Try It

```bash
gem install dspy
```

Or, if you want the wider ecosystem pieces:

```ruby
gem "dspy"
gem "dspy-openai"
gem "dspy-anthropic"
gem "dspy-gemini"
gem "dspy-ruby_llm"
```

The docs are at [oss.vicente.services/dspy.rb](https://oss.vicente.services/dspy.rb/), and the full release notes are on GitHub.
