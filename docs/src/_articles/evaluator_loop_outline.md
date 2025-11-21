# Evaluator Loop Workflow Series – Outline

Great outputs rarely ship on the first LLM pass. The win comes from a tight loop: propose, critique, refine—without setting your budget on fire. This series shows how DSPy.rb wires that loop for AI SDRs (and beyond) so teams ship requirement-backed copy instead of vibe-only drafts.

## Evaluator Loops & Self-Improving Workflows
Evaluator–optimizer is a two-model handshake: the generator proposes, the evaluator scores and prescribes fixes, and the loop applies those deltas until the evaluator is satisfied. Unlike “LLM as judge,” the evaluator here is wired for actionable guidance, not a one-shot verdict.[^1]

**When to reach for it?** Anthropic’s litmus test fits neatly: (1) you have clear criteria, and (2) iterative feedback measurably improves the draft because the evaluator can articulate concrete edits.[^1] Think of it as the LLM equivalent of a writer cycling through edits on a Google Doc.

Our running example is the AI SDR requirements loop: the generator drafts outbound copy; the evaluator returns a decision, weighted requirement coverage, and next-step recommendations; the loop iterates within a token budget until approval. Typical evaluator prompts include: “Did we explicitly name the RevOps pain and quantify its cost?”, “Does the proof point cite a customer metric?”, and “Is the CTA specific and actionably phrased for LinkedIn?” Common recommendations fed back into the generator: “Add a 2-sentence proof with a % lift,” “Tighten the CTA to a single action (share a blocker screenshot),” “Dial tone to ‘consultative’ and reduce hype adjectives.” That same pattern generalizes to other domains:
- Literary translation that needs nuance passes the translator missed on the first cut.[^1]
- Complex search/research where an evaluator decides whether another retrieval + synthesis round is warranted.[^1]

Budget, not iterations, is the guardrail—unlike DSPy::ReAct-style loops that often cap turns. We cap total tokens (default 9k) so the loop stays cost-aware while allowing as many useful passes as the budget permits.[^2]

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
[^2]: “Building Your First ReAct Agent in Ruby,” DSPy.rb blog, July 2025. citeturn0search2
