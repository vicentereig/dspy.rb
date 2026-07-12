---
layout: blog
title: "DSPy.rb 1.0.0"
description: "DSPy.rb 1.0.0 lands after months of smaller revisions: TOON/BAML, RubyLLM, Anthropic structured outputs, stronger observability, safer coercion, and multimodal document support."
date: 2026-04-11
author: "Vicente Reig"
category: "Release"
reading_time: "4 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/dspy-rb-1-0-0-release/"
image: /images/og/dspy-rb-1-0-0-release.png
---

At some point, continuing to call a library `0.34.4` stops sounding careful and starts sounding like you have commitment issues.

DSPy.rb 1.0.0 is out. If you've been on the `0.3x` releases, `1.0.0` should feel familiar. This release marks the `1.x` line as the stable API rather than introducing a new programming model.

This release comes after months of smaller revisions, which is the least exciting way to improve software and also the only one that works. You fix edge cases. You clean up boundaries. You delete the abstractions you wrote when you were younger and more confident.

## What Changed on the Way to 1.0

Over the last stretch of releases, DSPy.rb tightened several boundaries that matter once programs run outside a demo.

TOON and BAML made structured prompting leaner. RubyLLM widened provider coverage without changing the programming model. Anthropic support got stricter and more predictable through strict mode and Beta structured outputs. Langfuse score reporting and observability made production behavior easier to inspect. Type coercion and JSON extraction got harder to break in boring, preventable ways. And multimodal document support closed one of the more visible gaps in the API.

None of this is especially flashy on its own. It does mean fewer application-specific workarounds around provider and parsing boundaries.

## What Lands in 1.0.0 Itself

The `1.0.0` release itself includes a smaller set of changes than the full road to 1.0:

- Anthropic PDF document support through `DSPy::Document`, `raw_chat`, and `Predict`
- GEPA evaluation runs that continue when an individual example fails
- safer sanitization for control characters in extracted JSON
- updated adapter SDK floors, with compatibility expressed through dependencies instead of runtime guardrails

The dependency floors make compatibility explicit at installation time instead of relying on runtime version checks.

## Why 1.0 Now

If you've been using the later `0.3x` releases, `1.0.0` should not feel like a dramatic reinvention. That would be suspicious. The point of a stable release is not to suddenly become a different library. The point is to admit the current one is coherent enough to depend on.

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
