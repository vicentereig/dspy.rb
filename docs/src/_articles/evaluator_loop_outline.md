# Evaluator Loop Workflow Series – Outline

## 1. Evaluator Loops & Self-Improving Workflows
- Define evaluator-optimizer pattern vs. single-shot “LLM as judge.”
- Walk LinkedIn slop loop lifecycle: generator emits draft + metadata, evaluator returns rubric score + recommendations, loop feeds deltas back until approval.
- Introduce “budget instead of max iterations” concept so readers know we cap cost, not arbitrary attempt count.

## 2. DSPy Hook Magic: Slop on a Budget
- Detail how DSPy module-level callbacks + event subscriptions let us observe `lm.tokens` inside the workflow.
- Derive the default ~3.6k-token budget from the recorded two-iteration cassette (~1.7k tokens/2 attempts ≈ 860 tokens per iteration => 4 attempts headroom).
- Show pseudo-code for the `TokenBudgetTracker`, the callback wiring, and how we surface `budget_exhausted` in `LoopResult`.

## 3. Tracking E2E Quality with DSPy::Evals
- Walk through the `DSPy::Evals.new(loop_module, metric: approved?)` snippet that ships in `examples/evaluator_loop.rb` so readers can replay canned prompts.
- Show how the composite metric penalizes extra attempts + budget burn so we can rank different model pairs against the same base prompts.
- Describe the future eval suite: final-output evals, generator/evaluator regression suites, and score delta gates.
- Discuss how eval fixtures reuse the same persona/topic seeds so we can compare rubric versions apples-to-apples.
- Mention CI hooks (e.g., fail PR if average evaluator score drops >0.02).

## 4. Observability (“o11y”) Dumps
- Include Langfuse screenshots or JSON dumps showing generator/evaluator spans + recommendation payloads per attempt.
- Highlight custom `token_budget.remaining` attributes so folks can watch budgets burn down in traces.
- Share troubleshooting story: seeing retries stall because tone sliders were missing, fixed by inspecting span payloads.
