# Evaluator Loop Workflow Series – Outline

## 1. Evaluator Loops & Self-Improving Workflows
- Define evaluator-optimizer pattern; call out how this differs from “LLM as a judge.”
- When to use it?
- Walk the AI SDR requirements loop: generator drafts outbound copy, evaluator returns decision + coverage + recommendations, loop applies deltas until approval. As Anthropic frames it, “one LLM call generates a response while another provides evaluation and feedback in a loop.”[^1]
- Ground when-to-use guidance with Anthropic’s criteria: “This workflow is particularly effective when we have clear evaluation criteria, and when iterative refinement provides measurable value. The two signs of good fit are, first, that LLM responses can be demonstrably improved when a human articulates their feedback; and second, that the LLM can provide such feedback. This is analogous to the iterative writing process a human writer might go through when producing a polished document.”[^1]
- Emphasize “budget instead of max iterations” (token budget gates the loop).
- Examples where evaluator-optimizer shines (per Anthropic): literary translation with iterative nuance fixes, and complex search tasks where the evaluator decides if more retrieval passes are warranted.[^1]

## 2. DSPy.rb Hooks and Conventions: Quality on a Budget
- Show how module-level subscriptions (`lm.tokens`) drive live token accounting.
- Derive the default 9k-token budget from recorded attempts (≈2.2k tokens/iteration ⇒ 4 attempts headroom).
- Pseudo-code: `TokenBudgetTracker`, subscription wiring, and the `RevisedPost` summary (coverage, attempts, budget flags).

## 3. Tracking E2E Quality (Future DSPy::Evals)
- Plan: attach DSPy::Evals for composite efficiency metrics and regression gates.
- Replay canned prompts to compare generator/evaluator pairs without full reruns.
- Gate changes with score deltas once Langfuse wiring is in place.

## 4. Observability (“o11y”) Dumps
- Include Langfuse span examples showing generator/evaluator attempts and recommendation payloads.
- Highlight `token_budget.remaining` attributes to visualize burn-down.
- Troubleshooting story: retries stalled when tone sliders were absent—fixed after inspecting span payloads.

[^1]: Anthropic, “Building effective agents,” Workflow: Evaluator-optimizer, Dec 19 2024. citeturn0search0
