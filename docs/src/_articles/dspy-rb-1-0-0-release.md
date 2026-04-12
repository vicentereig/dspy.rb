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

DSPy.rb 1.0.0 is out. If you've been on the `0.3x` releases, `1.0.0` should feel familiar. This is the version where we stop pretending the library is still a promising young upstart and admit it has become dependable, which is about the nicest thing software can be without becoming a chair.

This release comes after months of smaller revisions, which is the least exciting way to improve software and also the only one that works. You fix edge cases. You clean up boundaries. You delete the abstractions you wrote when you were younger and more confident. You choose, again and again, not to leave the raccoon in the ventilation system for someone else.

Eventually the library becomes the thing nobody mentions, which is what happens when people refuse to stop maintaining something long after it would have been socially acceptable to quit. That's where DSPy.rb is now.

## What Changed on the Way to 1.0

Over the last stretch of releases, DSPy.rb picked up the kinds of improvements that make a framework feel dependable instead of merely interesting.

TOON and BAML made structured prompting leaner. RubyLLM widened provider coverage without changing the programming model. Anthropic support got stricter and more predictable through strict mode and Beta structured outputs. Langfuse score reporting and observability made production behavior easier to inspect. Type coercion and JSON extraction got harder to break in boring, preventable ways. And multimodal document support closed one of the more visible gaps in the API.

None of this is especially flashy on its own. Together, it changes the feel of the system from "promising" to "usable without a side career in workaround management," which is how most software becomes respectable.

## What Lands in 1.0.0 Itself

The `1.0.0` release itself includes a smaller set of changes than the full road to 1.0, but they are the right kind of finishing moves:

- Anthropic PDF document support through `DSPy::Document`, `raw_chat`, and `Predict`
- GEPA eval runs that no longer disintegrate because one example decided to become folklore
- safer sanitization for control characters in extracted JSON
- updated adapter SDK floors, with compatibility expressed through dependencies instead of runtime guardrails

That last one matters more than it sounds. A lot of "stability" in libraries is really just how many ways they fail at the seams. Tightening those seams is less glamorous than announcing a new agent architecture, but it is the difference between "cool demo" and "I can build on this without developing a private folklore of exceptions."

## Why 1.0 Now

Because the library is stable now.

If you've been using the later `0.3x` releases, `1.0.0` should not feel like a dramatic reinvention. That would be suspicious. The point of a stable release is not to suddenly become a different library. The point is to admit the current one is coherent enough to depend on.

## Thank You

Thanks to everyone who has contributed to DSPy.rb over the life of the project and helped drag it into legitimate-software status:

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

Open source is still a bizarre system. People from different places, with fully separate lives, voluntarily spend time improving a library so it can become more stable for strangers on the internet. That is generous, slightly irrational, and deeply appreciated.

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

---

*Take DSPy.rb 1.0.0 for a spin and go build something with substance.*
