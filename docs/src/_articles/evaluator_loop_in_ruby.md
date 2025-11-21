---
layout: blog
title: "Evaluator Loops in Ruby: Ship Sales Pitches with Confidence"
description: "Use DSPy.rb signatures, callbacks, and token budgets to iterate sales pitches with a lightweight generator and a heavier CoT evaluator."
date: 2025-11-21
author: "Vicente Reig"
category: "Workflow"
reading_time: "4 min read"
image: /images/og/evaluator-loop-in-ruby.png
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/evaluator_loop_in_ruby/"
---

# Evaluator Loop Workflow Series – Outline

Great outputs rarely ship on the first LLM pass. The win comes from a tight loop: propose, critique, refine—without setting your budget on fire. This series shows how DSPy.rb wires that loop for sales pitches (and other workflows) so teams ship requirement-backed copy instead of vibe-only drafts.

## Evaluator Loops & Self-Improving Workflows
Evaluator–optimizer is a two-model handshake: the generator proposes, the evaluator scores and prescribes fixes, and the loop applies those deltas until the evaluator is satisfied. Unlike “LLM as judge,” the evaluator here is wired for actionable guidance, not a one-shot verdict.[^1]

**When to reach for it?** Anthropic’s litmus test fits neatly: (1) you have clear criteria, and (2) iterative feedback measurably improves the draft because the evaluator can articulate concrete edits.[^1] Think of it as the LLM equivalent of a writer cycling through edits on a Google Doc.

[Our running example](https://github.com/vicentereig/dspy.rb/blob/feature/evaluator-loop-blog/examples/evaluator_loop.rb) is the SalesPitchWriter loop: the generator drafts outbound copy with a lightweight Anthropic model; the evaluator uses a heavier Anthropic model in Chain-of-Thought mode to return a decision, weighted coverage, and next-step recommendations; the loop iterates within a token budget until approval. Typical evaluator prompts include: “Did we state the buyer pain and quantify its cost?”, “Is there a proof metric?”, and “Is the CTA specific and single-action?” Common recommendations fed back into the generator: “Add a 2-sentence proof with a % lift,” “Tighten the CTA to one action,” “Dial tone to consultative and cut hype adjectives.” That same pattern generalizes to other domains:
- Literary translation that needs nuance passes the translator missed on the first cut.[^1]
- Complex search/research where an evaluator decides whether another retrieval + synthesis round is warranted.[^1]

These Signatures turn our LLM invocations into functions (from [`examples/evaluator_loop.rb`](https://github.com/vicentereig/dspy.rb/blob/feature/evaluator-loop-blog/examples/evaluator_loop.rb)):

```ruby
class GenerateLinkedInArticle < DSPy::Signature
  description "Draft a concise sales pitch that embraces a persona's preferences."

  input do
    const :topic_seed, TopicSeed, description: "Noun-phrase or event plus the requested take slider for the pitch."
    const :vibe_toggles, VibeToggles, description: "Tone sliders for cringe, hustle, and vulnerability."
    const :structure_template, StructureTemplate, description: "High-level outline the pitch should follow."
    const :hashtag_band, HashtagBand, default: HashtagBand.new, description: "Hashtag min/max and auto-brand toggle."
    const :length_cap, LengthCap, default: LengthCap.new, description: "Length mode plus optional token/character caps."
    const :recommendations, T::Array[Recommendation], default: [], description: "Prior evaluator notes to fold in."
  end

  output do
    const :post, String, description: "Sales-ready copy that reflects the requested toggles."
    const :hooks, T::Array[String], description: "Hook options the evaluator can judge."
  end
end

class EvaluateLinkedInArticle < DSPy::Signature
  description "Score a generated sales pitch and provide actionable feedback."

  input do
    const :post, String, description: "Latest pitch draft."
    const :topic_seed, TopicSeed, description: "Target topic phrase and take."
    const :vibe_toggles, VibeToggles, description: "Cringe/hustle/vulnerability sliders to enforce."
    const :structure_template, StructureTemplate, description: "Expected outline (story → lesson → CTA, listicle, etc.)."
    const :hashtag_band, HashtagBand, description: "Allowed hashtag range and auto-brand toggle."
    const :length_cap, LengthCap, description: "Requested length mode or explicit caps."
    const :recommendations, T::Array[Recommendation], description: "History of edits already suggested."
    const :hooks, T::Array[String], description: "Hooks supplied by the generator."
    const :attempt, Integer, description: "1-indexed attempt counter."
  end

  output do
    const :decision, EvaluationDecision, description: "Whether this draft is approved or needs revision."
    const :feedback, String, description: "Narrative explanation of the rubric score."
    const :recommendations, T::Array[Recommendation], description: "Structured edits the generator should apply next."
    const :self_score, Float, description: "Pitch quality score between 0.0 and 1.0 inclusive."
  end
end
```
Full definitions live in [`examples/evaluator_loop.rb`](https://github.com/vicentereig/dspy.rb/blob/feature/evaluator-loop-blog/examples/evaluator_loop.rb) (kept in sync with this article).

Budget, not iterations, is the guardrail—unlike DSPy::ReAct-style loops that often cap turns. We cap total tokens (default 9k) so the loop stays cost-aware while allowing as many useful passes as the budget permits.[^2]

Evaluation loop driver: the module runs `GenerateLinkedInArticle` with a light Anthropic Haiku model, then calls `EvaluateLinkedInArticle` 
via Chain-of-Thought on a heavier Anthropic Sonnet model, repeating while budget remains and the evaluator still wants changes.

```ruby
class SalesPitchWriterLoop < DSPy::Module
  subscribe 'lm.tokens', :count_tokens
  
  def forward(**input_values)
    while tracker.remaining.positive?
      draft = generator.call(**input_values.merge(recommendations: recommendations))
      evaluation = evaluator.call(post: draft.post,
                                  topic_seed: input_values[:topic_seed],
                                  vibe_toggles: input_values[:vibe_toggles],
                                  structure_template: input_values[:structure_template],
                                  hashtag_band: hashtag_band,
                                  length_cap: length_cap,
                                  recommendations: recommendations,
                                  hooks: draft.hooks,
                                  attempt: attempt_number)
      recommendations = evaluation.recommendations || []
      break if evaluation.decision == EvaluationDecision::Approved
    end
  end

  def count_tokens(_event_name, attributes)
    tracker = @active_budget_tracker
    return unless tracker

    prompt = attributes[:input_tokens] 
    completion = attributes[:output_tokens] 
    total = attributes[:total_tokens] 

    tracker.track(
      prompt_tokens: prompt&.to_i,
      completion_tokens: completion&.to_i,
      total_tokens: total&.to_i
    )
  end
end
```

Full loop logic lives in `EvaluatorLoop::SalesPitchWriterLoop` in `examples/evaluator_loop.rb`.

## 2. DSPy.rb Hooks and Conventions: Quality on a Budget
We subscribe to `lm.tokens` to track prompt/completion usage and emit a `sdr_loop.budget` event each turn. Budget is capped by tokens (10k in this run) instead of hard iteration counts—exactly how `SalesPitchWriterLoop` is wired.

Latest Langfuse trace (Nov 21, 2025 — generator on Anthropic Haiku, evaluator on Anthropic Sonnet CoT):

```
└─ EvaluatorLoop::SalesPitchWriterLoop.forward (ed89899bac229240)
   └─ EvaluatorLoop::SalesPitchWriterLoop.forward (ee155baa7ea3c707)
      └─ EvaluatorLoop::SalesPitchWriterLoop.forward (25d6c7cb5ce67556)
         ├─ DSPy::ChainOfThought.forward (a4ae3f51d105e27e)   # evaluator
         │  ├─ DSPy::Predict.forward (2c09e511ef4112e3)
         │  │  └─ llm.generate (1693f7a4893de528)
         │  ├─ chain_of_thought.reasoning_complete (2f6cf25f6e671e4e)
         │  └─ chain_of_thought.reasoning_metrics (7bb07c8d57d3041b)
         └─ DSPy::Predict.forward (886c35a6382591b6)          # generator
            └─ llm.generate (a19c643a7a7ebad2)
```

Run stats:
- Attempts: 1 (approved)
- Token budget: 5,926 / 10,000 used (not exhausted)
- Total cost (Langfuse): ~$0.0258

The tree makes it easy to see which model handled each step, how many hops burned budget, and whether the evaluator demanded another pass.


[^1]: Anthropic, “Building effective agents,” Workflow: Evaluator-optimizer, Dec 19 2024. citeturn0search0
[^2]: “Building Your First ReAct Agent in Ruby,” DSPy.rb blog, July 2025. citeturn0search2
