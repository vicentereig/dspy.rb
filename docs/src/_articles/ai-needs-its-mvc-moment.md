---
layout: blog
title: "AI Needs Its MVC Moment"
description: "Why LLM application development today looks like web development in 2003, and how programmatic frameworks like DSPy.rb are bringing the discipline that made Rails revolutionary."
date: 2025-12-23
author: "Vicente Reig"
category: "Leadership"
reading_time: "7 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/ai-needs-its-mvc-moment/"
image: /images/og/ai-needs-its-mvc-moment.png
---

If you're a CTO or Head of Engineering who lived through the early 2000s web development era, the current state of LLM application development might feel eerily familiar.

Back then, every team built web applications differently. Business logic lived in templates. Database queries scattered across presentation layers. No standardized patterns. No observability. Debugging meant `print` statements and prayer.

Then Rails arrived with MVC, and everything changed. Not because MVC was new (it wasn't), but because Rails provided an opinionated, standardized way to build applications that teams could reason about, debug, and maintain.

**LLM applications are at that same inflection point today.**

## The Current State of Chaos

Walk into any engineering organization building with LLMs, and you'll find:

**Prompt Sprawl**: Prompts scattered across codebases, version-controlled (maybe) through git, with no standardized structure. Engineers copy-paste from ChatGPT. "Prompt engineering" means trial and error with no reproducibility.

**Agent Spaghetti**: Multi-step AI workflows where it's impossible to understand what the system decided, why it decided it, or where it failed. When an agent makes a bad decision, good luck tracing back to the root cause.

**Evaluation Theater**: Teams claiming "90% accuracy" based on vibes and a handful of test cases. No systematic evaluation. No regression testing. No way to know if that prompt change actually helped or hurt.

**Observability Gaps**: Traditional APM tools designed for request-response cycles can't capture the reasoning chains, tool calls, and iterative loops that define agent behavior. You can see the HTTP request went out, but not what the AI was thinking.

**Vendor Lock-in Through Chaos**: Every provider has different APIs, different response formats, different capabilities. Teams write brittle adapter code that breaks with every API update.

Sound familiar? It should. This is exactly what web development looked like before standardized frameworks.

## What MVC Actually Solved

The genius of Rails wasn't the code—it was the constraints.

By standardizing where business logic lived (models), how data flowed through the system (controllers), and how presentation happened (views), Rails made applications **legible**. Any Rails developer could walk into any Rails codebase and immediately understand the architecture.

More importantly, standardization enabled an ecosystem. Once everyone agreed on patterns, you could build tools that worked everywhere: debuggers, profilers, test frameworks, deployment pipelines.

The observability story is instructive. Before standardized patterns, monitoring meant custom instrumentation for every application. After? Tools like New Relic could automatically instrument any Rails app because they knew exactly where to hook in.

## What DSPy.rb Brings to LLM Development

DSPy.rb applies the same philosophy to LLM applications. Instead of prompt strings and API calls, you define **Signatures**—typed contracts between your application and language models:

```ruby
class CustomerIntent < DSPy::Signature
  description "Classify customer support messages by intent and urgency"

  input do
    const :message, String
    const :customer_tier, String
  end

  output do
    const :intent, Intent       # Type-safe enum
    const :urgency, Urgency     # Not a string—a real type
    const :confidence, Float
  end
end
```

This isn't just syntax. It's a fundamental shift in how you build:

**Contracts, Not Prompts**: Your team reasons about interfaces, not prompt wording. The prompt becomes an implementation detail that can be optimized automatically.

**Type Safety**: When the LLM returns `"high"` as a string instead of `Urgency::High`, the framework catches it. Before production. Every time.

**Composable Modules**: Build complex workflows from simple, testable components. The `ChainOfThought` module adds reasoning. The `ReAct` module adds tool use. Stack them like Lego blocks.

## Observability That Actually Works

Here's where the MVC parallel becomes concrete. Because DSPy.rb knows the structure of your application—what Signatures you're calling, what reasoning steps are happening, what tools are being invoked—it can provide observability that generic tools cannot.

Every operation automatically emits structured events following OpenTelemetry semantic conventions:

- **Generation spans** capture LLM calls with token usage, timing, and model details
- **Chain spans** show reasoning steps in ChainOfThought workflows
- **Agent spans** track ReAct iterations with thought-action-observation loops
- **Tool spans** record external tool invocations within agent workflows

This isn't bolted-on logging. It's architectural. The framework knows what's happening because the patterns are standardized.

**Score Reporting** takes this further. With `DSPy.score()`, you can export evaluation metrics directly to Langfuse:

```ruby
evaluator = DSPy::Evals.new(
  program,
  metric: accuracy_metric,
  export_scores: true
)

result = evaluator.evaluate(test_examples)
# Every example gets a score in Langfuse
# Overall batch metrics tracked automatically
```

When your customer intent classifier starts degrading in production, you'll know—not because users complained, but because your monitoring caught the score drop.

## The Enterprise Reality

For CTOs and Heads of Engineering, the question isn't whether AI will be part of your stack. It's how you'll govern it.

**Reproducibility**: Can you reproduce a failure from last week? With standardized traces attached to every prediction, you can replay the exact inputs, reasoning, and outputs that led to any decision.

**Debugging**: When an agent hallucinates, can your team trace back to why? Hierarchical spans show exactly which reasoning step went wrong and what context it had.

**Evaluation**: Before deploying a prompt change, can you prove it won't regress? Built-in evaluation frameworks with systematic metrics make this a CI/CD step, not a hope.

**Cost Control**: Are you burning through tokens on unnecessary retries? Token usage tracked at every level, exportable to your cost monitoring systems.

**Team Productivity**: Can a new engineer understand your AI workflows? Standardized patterns mean onboarding takes days, not months.

## The Path Forward

The early 2000s web chaos resolved through adoption of standardized frameworks. Teams that adopted Rails (or Django, or Spring) could move faster, hire easier, and build more reliable systems.

The same consolidation is coming to LLM applications. The question for engineering leaders is whether to adopt standardized patterns now—while you can still shape your architecture—or later, when you're migrating spaghetti.

DSPy.rb represents one path forward: type-safe contracts, composable modules, built-in observability, and systematic evaluation. It's opinionated by design. The constraints are the feature.

The teams building production AI systems today will look back at this moment the way we look back at pre-Rails web development. The winners will be those who recognized the pattern and adopted discipline early.

AI needs its MVC moment. It's happening now.

---

*DSPy.rb is open source and available at [github.com/vicentereig/dspy.rb](https://github.com/vicentereig/dspy.rb). The observability features described here integrate with Langfuse via OpenTelemetry and require the optional `dspy-o11y` and `dspy-o11y-langfuse` gems.*
