---
layout: blog
title: "AI Needs Its MVC Moment"
description: "Prompt engineering is just programming. Treat it that way and AI systems start working like real software."
date: 2025-12-23
author: "Vicente Reig"
category: "Leadership"
reading_time: "5 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/ai-needs-its-mvc-moment/"
image: /images/og/ai-needs-its-mvc-moment.png
---

Prompt engineering is just programming.

There's an entire industry built around treating prompts as a special discipline—courses, certifications, job titles. But I keep seeing the same failure mode: a tool errors, the stacktrace lands in the prompt, and nobody notices until a customer complains that the output has nothing to do with their marketing materials.

The team wasn't treating the prompt as real code. They were treating it as something else. Something that required different rules.

That's the problem.

## The Discipline We Already Know

I lived through the early 2000s web era. Every team built things differently, and every project was a mess in its own special way. Then Rails arrived, and the key insight wasn't MVC—it was that web development was just programming, and programming already had answers for managing complexity.

We're making the same mistake with AI. We've convinced ourselves that because LLMs were new, we need new rules. And turns out the old boring rules still work wonders.

We're also moving past the chatbot era. Everyone built chatbots that pushed the cognitive load onto users—figure out what to ask, interpret the response, decide if it's right. The next step is repeatable reasoning systems that do the work reliably, every time.

## What This Actually Looks Like

Here's disciplined LLM development:

```ruby
class CustomerIntent < DSPy::Signature
  description "Classify customer support messages"

  input  { const :message, String }
  output { const :intent, Intent; const :urgency, Urgency }
end

classifier = DSPy::Predict.new(CustomerIntent)
result = classifier.call(message: "My payment failed")
# => result.intent == Intent::Billing, result.urgency == Urgency::High
```

A contract that governs the relationship with the LLM.

When the LLM returns `"high"` as a string instead of `Urgency::High`, the framework catches it. Before production. Because that's what type systems do. Just plain and boring engineering.

The prompt becomes an implementation detail. You can [optimize it automatically](/optimization/prompt-optimization/). You can swap models without changing application code. You can write tests that actually test behavior, not string matching.

## The Questions You Can't Answer Today

Walk into most organizations building with LLMs and ask:

Can you reproduce the failure from last Tuesday? No structured traces. No replay capability. Just Slack threads full of theories.

When the agent hallucinated, which reasoning step went wrong? Multi-step workflows with no observability into what the system decided, why it decided it, or where the logic broke.

Did that prompt change help or hurt? "90% accuracy" based on vibes and a handful of test cases. No systematic evaluation. No regression testing.

Do you know how the model reached that prediction, regardless of whether it was accurate? Most teams can't answer this even when things go right.

These are table stakes for any production system. We've been solving them for decades in traditional software.

## Standardized Patterns Enable Tooling

When your code follows standardized patterns, the tooling can actually help. [Signatures](/core-concepts/signatures/) define contracts. [Modules](/core-concepts/modules/) compose behavior. The framework knows the structure of your application, so when something goes wrong, you trace it in minutes instead of days.

[Evaluation](/optimization/evaluation/) becomes a CI/CD step. Before deploying a prompt change, you prove it won't regress.

## What Now

Pick one classifier or extractor your team maintains. Define it as a [Signature](/core-concepts/signatures/). Add one [evaluation metric](/advanced/custom-metrics/). Deploy it with [tracing enabled](/production/observability/).

See what changes when you treat LLM code like real software.

The debugging sessions get shorter. The "works on my machine" prompts disappear. Vibes give way to actual metrics.

---

*DSPy.rb is open source at [github.com/vicentereig/dspy.rb](https://github.com/vicentereig/dspy.rb). I explored these themes in my recent talk, [Turning Messy Prompts into Repeatable Reasoning Systems](https://vicente.services/talks/2025/12/turning-messy-prompts-into-repeatable-reasoning-systems/).*
