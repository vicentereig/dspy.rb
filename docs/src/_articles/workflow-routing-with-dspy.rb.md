---
layout: blog
title: "Build a Workflow Router in Ruby"
description: "Route every ticket to the right Language Model, only escalate to heavy LLMs when needed, keep every hop observable, and never touch a handwritten prompt along the way."
date: 2025-11-16
author: "Vicente Reig"
category: "Workflow"
reading_time: "4 min read"
image: /images/workflow-routing.webp
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/workflow-routing-with-dspy.rb/"
---

Successful LLM implementations rely on simple, composable patterns instead of sprawling frameworks. 
[DSPy.rb](https://github.com/vicentereig/dspy.rb) lets you compose that workflow with typed signatures so every prompt 
is generated programmatically instead of hand-written. 

This simple classifier-plus-specialists layout becomes essential once a single catch-all prompt starts to creak—complex requests need different context, follow-up  instructions, or even different models.
For the impatient, jump straight to the sample script in [`examples/workflow_router.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/workflow_router.rb).

```mermaid
flowchart LR
    Incoming["Support ticket\n(message)"]
    subgraph RouterBox["SupportRouter (DSPy::Module)"]
        direction TB
        Classifier["RouteSupportTicket\nDSPy::Predict"]
        Router["Handler dispatch\n+ RoutedTicket build"]
    end

    Billing["DSPy::Predict.new(SupportPlaybooks::Billing)"]
    General["DSPy::Predict.new(SupportPlaybooks::GeneralEnablement)"]
    Technical["DSPy::ChainOfThought.new(SupportPlaybooks::Technical)"]

    Result["RoutedTicket\ncategory • confidence • model_id\nsummary • steps • tags"]

    style RouterBox stroke-dasharray: 5 5

    Incoming --> Classifier --> Router
    Router -->|billing| Billing --> Result
    Router -->|general| General --> Result
    Router -->|technical| Technical --> Result
```

Rather than letting one mega prompt struggle to cover every
edge case, [DSPy.rb](https://github.com/vicentereig/dspy.rb) lets you compose a lightweight classifier plus a handful
of specialized predictors that stay focused and easy to optimize.

## Why a workflow before you build an agent?

Workflows[^1] keep LLMs and tools on predefined code paths—you still need to tune prompts, choose models, and explicitly wire every branch—so you retain deterministic control while you validate the solution. Once you've validated routing and specialized handlers, you can [upgrade specific branches to autonomous ReAct agents](https://vicentereig.github.io/dspy.rb/blog/articles/react-agent-tutorial/) without rewriting the classifier.

## Architecture at a glance

Breaking down the router into components, we can delegate their predictions to specific models based on cost or performance. 

| Component                     | Prompting Technique                                                                 | Default Model                          | Purpose |
|-------------------------------|--------------------------------------------------------------------------------------|----------------------------------------|---------|
| RouteSupportTicket classifier | [`DSPy::Predict`](https://vicentereig.github.io/dspy.rb/core-concepts/predictors/)           | `anthropic/claude-haiku-4-5-20251001`  | Categorize each ticket + explain reasoning |
| Billing / General playbooks   | [`DSPy::Predict`](https://vicentereig.github.io/dspy.rb/core-concepts/predictors/#dspypredict) | `anthropic/claude-haiku-4-5-20251001`  | Cheap follow-up guidance for routine issues |
| Technical playbook            | [`DSPy::ChainOfThought`](https://vicentereig.github.io/dspy.rb/core-concepts/predictors/#dspychainofthought) | `anthropic/claude-sonnet-4-5-20250929` | Deeper reasoning + escalation steps for tricky tickets |
| SupportRouter                 | [`DSPy::Module`](https://vicentereig.github.io/dspy.rb/core-concepts/modules/)      | `anthropic/claude-haiku-4-5-20251001`  | Orchestrates classifier, handlers, and output struct |


1. **A signature to anchor ticket classification** – one `DSPy::Predict` call decides which category is the best fit and reports confidence/reasoning:
   ```ruby
   class RouteSupportTicket < DSPy::Signature
     input  { const :message, String }
     output do
       const :category, TicketCategory
       const :confidence, Float
       const :reason, String
     end
   end

   classifier = DSPy::Predict.new(RouteSupportTicket)
   classification = classifier.call(message: 'hello hello')
```
2. **Specialized playbooks** – each downstream signature tweaks the description/goal while reusing the shared schema. They are independent and they are predicted by different prompting techniques as need.
   ```ruby
   class SupportPlaybooks::Billing < DSPy::Signature
     include SharedSchema
     description "Resolve billing or refund issues with policy-aware guidance."
   end

   class SupportPlaybooks::Technical < DSPy::Signature
     include SharedSchema
     description "Handle technical or outage reports with diagnostic steps."
   end

   class SupportPlaybooks::GeneralEnablement < DSPy::Signature
     include SharedSchema
     description "Answer broad questions or point folks to self-serve docs."
   end
   ```  
   Instead of writing prompts, you adjust the signature description and let DSPy compile the right instructions for each specialized LLM call.
3. **Router module** – plain Ruby orchestrator that wires classifier + handlers, ensures every branch returns the same struct, and records the exact model that ran.
## Touring the Router Workflow

The full walkthrough lives in [`examples/workflow_router.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/workflow_router.rb). Notice that every interaction goes through a `DSPy::Signature`, so we never drop into raw prompt strings—inputs/outputs are typed once and automatically compiled into prompts behind the scenes. Key pieces:

1. **Typed categories solve mystery intents**  
   ```ruby
   class TicketCategory < T::Enum
     enums do
       General = new('general')
       Billing = new('billing')
       Technical = new('technical')
     end
   end
   ```  
   When the classifier returns a `TicketCategory`, the router can’t receive unexpected strings like `"refund?"` or `"tech_support"`; all branches are exhaustively checked at compile time.

2. **Shared playbook schema keeps outputs uniform**  
   ```ruby
   module SupportPlaybooks
     module SharedSchema
       def self.included(base)
         base.class_eval do
           input  { const :message, String }
           output do
             const :resolution_summary, String
             const :recommended_steps, T::Array[String]
             const :tags, T::Array[String]
           end
         end
       end
     end
   end
   ```  
   Every follow-up predictor returns the same fields, so downstream logging/analytics doesn’t need per-branch adapters.

3. **Per-stage specialized models keep costs and performance predictable**  
   ```ruby
   billing_follow_up = DSPy::Predict.new(SupportPlaybooks::Billing)
   billing_follow_up.configure do |config|
     config.lm = DSPy::LM.new(LIGHTWEIGHT_MODEL, api_key: ENV['ANTHROPIC_API_KEY'])
   end

   technical_follow_up = DSPy::ChainOfThought.new(SupportPlaybooks::Technical)
   technical_follow_up.configure do |config|
     config.lm = DSPy::LM.new(HEAVY_MODEL, api_key: ENV['ANTHROPIC_API_KEY'])
   end
   ```  
   Each handler pins its own LM (`LIGHTWEIGHT_MODEL` vs `HEAVY_MODEL`), so moving billing/general flows to a cheaper Haiku snapshot or moving technical flows to Sonnet is just an env tweak, not a code change.

4. **SupportRouter centralizes dispatch + telemetry context**  
   ```ruby
   class SupportRouter < DSPy::Module
     def forward_untyped(**input_values)
       classification = @classifier.call(**input_values)
       handler = @handlers.fetch(classification.category, @handlers[@fallback_category])
       specialized = handler.call(**input_values)
       RoutedTicket.new(category: classification.category,
                        model_id: handler.lm&.model_id || DSPy.config.lm&.model_id,
                        confidence: classification.confidence,
                        reason: classification.reason,
                        resolution_summary: specialized.resolution_summary,
                        recommended_steps: specialized.recommended_steps,
                        tags: specialized.tags)
     end
   end
   ```  
   Because it subclasses `DSPy::Module`, the router names the root span for every request; Langfuse/Honeycomb/Datadog see a single parent trace, and the `RoutedTicket` struct captures which LM actually answered so no span is orphaned.

Because everything is just Ruby, swapping a handler for DSPy’s evaluation modules, attaching tracing subscribers, or injecting feature flags takes minutes.

## Observability and tracing benefits

`lf traces get <TRACE_ID> -f json` (via the open-source [langfuse-cli](https://github.com/vicentereig/lf-cli)) drops classifier + specialist spans straight into my editor, so we can reason about cost/perf without spelunking dashboards. The November 16, 2025 traces surfaced three fast signals:

- General requests: everything stays on `claude-haiku-4-5-20251001`, ~2k tokens, 4.37 s total—cheap tiers cover FAQs.
- Technical incidents: Haiku routes (957 tokens / 1.92 s) before escalating to `claude-sonnet-4-5-20250929` for the 1,292 token / 12.39 s chain-of-thought hop—expensive capacity only burns when it’s justified.
- Billing escalations: still close on Haiku (≈2.1k tokens, 6.56 s end-to-end), so refunds stay on the lightweight tier.

Those traces form a tree you can paste into docs, incidents, or dashboards to explain exactly what ran for each customer request:

```text
Trace abd69193932e86eeb0de30a3ccd72c9e — SupportRouter.forward (category: general; model: anthropic/claude-haiku-4-5-20251001)
  message: What limits apply to the new analytics workspace beta?
└── SupportRouter.forward [4.37s]
    ├── DSPy::Predict.forward [1.71s]
    │   └── llm.generate (RouteSupportTicket) → claude-haiku-4-5-20251001 [1.71s]
    └── DSPy::Predict.forward [2.65s]
        └── llm.generate (SupportPlaybooks::GeneralEnablement) → claude-haiku-4-5-20251001 [2.65s]


Trace fc3cde8c24b24e0d7737603983e45888 — SupportRouter.forward (category: technical; model: anthropic/claude-sonnet-4-5-20250929)
  message: Device sensors stopped reporting since last night's deployment. Can you help me roll back?
└── SupportRouter.forward [14.31s]
    ├── DSPy::Predict.forward [1.92s]
    │   └── llm.generate (RouteSupportTicket) → claude-haiku-4-5-20251001 [1.92s]
    └── DSPy::ChainOfThought.forward [12.39s]
        ├── DSPy::Predict.forward [12.39s]
        │   └── llm.generate (SupportPlaybooks::Technical) → claude-sonnet-4-5-20250929 [12.39s]
        ├── chain_of_thought.reasoning_complete (SupportPlaybooks::Technical)
        └── chain_of_thought.reasoning_metrics (SupportPlaybooks::Technical)


Trace 20318579a66522710637f10d33be8bee — SupportRouter.forward (category: billing; model: anthropic/claude-haiku-4-5-20251001)
  message: My account was charged twice for September and the invoice shows an unfamiliar add-on.
└── SupportRouter.forward [6.56s]
    ├── DSPy::Predict.forward [2.69s]
    │   └── llm.generate (RouteSupportTicket) → claude-haiku-4-5-20251001 [2.68s]
    └── DSPy::Predict.forward [3.86s]
        └── llm.generate (SupportPlaybooks::Billing) → claude-haiku-4-5-20251001 [3.86s]
```

## Run it locally

```bash
echo "ANTHROPIC_API_KEY=sk-ant-..." >> .env
bundle install
bundle exec ruby examples/workflow_router.rb
```

Sample output (truncated):

```
🗺️  Routing 3 incoming tickets...

📨  INC-8721 via email
    Input: My account was charged twice for September and the invoice shows an unfamiliar add-on.
    → Routed to billing (92.4% confident)
    → Follow-up model: anthropic/claude-haiku-4-5-20251001
    Summary: Refund the duplicate charge and confirm whether the add-on was provisioned.
    Next steps:
      1. Verify September invoices in Stripe...
      2. Issue refund if duplicate...
      3. Email customer with receipt + policy reminder.
    Tags: refund, finance-review
```

Notice how every branch produces traceable metadata: we know which LM responded, why it was selected, and which next steps were generated. That data is gold for analytics or human-in-the-loop review.

## Adapt it to your stack

- Swap the classifier for a lightweight heuristic or a fine-tuned model if you already track intents elsewhere.
- Feed historical tickets into DSPy’s evaluation helpers to benchmark routing accuracy before shipping.
- Attach [`DSPy::Callbacks`](https://vicentereig.github.io/dspy.rb/core-concepts/module-runtime-context/#lifecycle-callbacks) subscribers so each routed request emits spans/metrics to Langfuse, Honeycomb, or Datadog; DSPy.rb modules support Rails-style lifecycle callbacks that wrap `forward`, letting you keep logging, metrics, context management, and memory operations out of business logic.
- Promote a branch to a [ReAct agent](https://vicentereig.github.io/dspy.rb/blog/articles/react-agent-tutorial/) later without rewriting the classifier—`SupportRouter` just needs a handler that responds to `call`.

Routing is a "minimum viable orchestration" pattern: fast to build, cheap to run, and powerful enough to keep your prompts specialized. Grab the example, swap in your own categories, and start measuring the gains before you reach for a full-blown agent.

[^1]: For a comprehensive guide on when to use workflows vs. agents, see Anthropic's [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents).
