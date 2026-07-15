---
layout: blog
title: "AI Needs Its MVC Moment"
description: "Apply familiar software disciplines to LLM programs: typed contracts, tests, traces, and repeatable evaluation."
date: 2025-12-23
author: "Vicente Reig"
category: "Leadership"
reading_time: "5 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/ai-needs-its-mvc-moment/"
image: /images/og/ai-needs-its-mvc-moment.png
---

LLM programs need the same disciplines as other application code: explicit contracts, repeatable tests, traces, and reviewable changes.

Without those controls, a tool error can land in a prompt and remain hidden until a customer reports unrelated output. The failure is not that prompts are unusual. It is that the application lacks a boundary the team can inspect and test.

## The Discipline We Already Know

I lived through the early 2000s web era. Every team built things differently, and every project was a mess in its own special way. Then Rails arrived. Its useful insight wasn't MVC itself. Web development was programming, and programming already had ways to manage complexity.

We're making the same mistake with AI. Because LLMs are new, we've assumed they need new rules. The old boring rules still apply: explicit contracts, tests, traces, and repeatable evaluation.

Chatbots push the cognitive load onto users: figure out what to ask, interpret the response, and decide whether it's right. Repeatable workflows move some of that work into code, where we can define outputs and test behavior.

## What This Actually Looks Like

Start with an explicit contract:

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

A signature defines the values the LLM receives and the values the application expects back.

When the LLM returns a value that cannot become an `Urgency` value, runtime validation rejects it before application code uses it. That boundary constrains shape; evaluation must still test whether the selected urgency is correct.

The prompt becomes an implementation detail behind the signature. An [optimizer](/dspy.rb/optimization/prompt-optimization/) can search supported instructions or demonstrations from examples, a metric, and an execution budget. You can also change models without changing the call site and test returned behavior instead of matching prompt strings.

## The Questions You Can't Answer Today

The production failure raises questions the prompt alone cannot answer:

Can you reproduce the failure from last Tuesday? Without structured traces or replay, all you have is a Slack thread full of theories.

When a multi-step workflow returned the wrong result, which step failed? Without traces, you cannot see the intermediate decisions or where the result changed course.

Did the prompt change help or hurt? "90% accuracy" based on vibes and a handful of test cases does not show whether the change regressed cases the team already handled.

What request, response, and intermediate results produced the prediction? Without that record, even a correct answer is hard to inspect.

Traditional software already gives us the relevant discipline: capture execution, test behavior, and compare changes against known cases.

## Standardized Patterns Enable Tooling

Patterns give tooling something concrete to inspect. [Signatures](/dspy.rb/core-concepts/signatures/) define inputs and outputs. [Modules](/dspy.rb/core-concepts/modules/) compose behavior. Traces can then record each module call, its inputs, and its outputs.

[Evaluation](/dspy.rb/optimization/evaluation/) can run in CI against a fixed set of examples. It cannot prove that a prompt change will never regress, but it can catch regressions in the cases you chose to keep.

## Apply the Discipline to One Program

Pick one classifier or extractor your team maintains. Define it as a [Signature](/dspy.rb/core-concepts/signatures/). Add an [evaluation metric](/dspy.rb/advanced/custom-metrics/) tied to the behavior you care about. Run a fixed example set before changes, then deploy with [tracing enabled](/dspy.rb/production/observability/).

When the next failure arrives, you have a trace to inspect, a case to add to the evaluation set, and a result you can compare against the next change.

---

*DSPy.rb is open source at [github.com/vicentereig/dspy.rb](https://github.com/vicentereig/dspy.rb). I explored these themes in my recent talk, [Turning Messy Prompts into Repeatable Reasoning Systems](https://vicente.services/talks/2025/12/turning-messy-prompts-into-repeatable-reasoning-systems/).*
