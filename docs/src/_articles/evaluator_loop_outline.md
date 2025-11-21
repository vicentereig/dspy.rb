# Evaluator Loop Workflow Series – Outline

## 1. Evaluator Loops & Self-Improving Workflows
- Define evaluator-optimizer pattern; call out how this differs from “LLM as a judge.”
- When to use it?
- Walk the AI SDR requirements loop: generator drafts outbound copy, evaluator returns decision + coverage + recommendations, loop applies deltas until approval.
- Emphasize “budget instead of max iterations” (token budget gates the loop).

## 2. DSPy Hook Magic: Requirements on a Budget
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
