# 016: Architecture Hardening Plan (Subscriptions, Concurrency, Structured Outputs)

Date: 2026-01-04

## Status

Proposed

## Context

Recent architecture review surfaced several systemic risks and sources of complexity:

- Module-level event subscriptions are instance-bound and never auto‑released, which can leak memory and keep listener callbacks alive for short‑lived modules.
- LM request correlation uses `Thread.current` while `LM#chat` runs under `Async::Sync`, so concurrent fibers on the same thread can overwrite request metadata and misattribute token usage.
- Structured outputs selection is coupled to adapter class names and instance variables; it ignores `data_format` and can emit a JSON‑only prompt even when TOON parsing is expected.
- Prompt formatting reads global config at render time, so prompt format can change if global config changes, leading to nondeterministic prompts across threads.
- Predictors and modules carry mutable instance state (`@last_input_values`, `@demos`, queues, cached LMs) and are not safe to share across parallel evaluations.
- Several methods/fields appear unused, adding cognitive load and potential maintenance risk.

We need a staged plan that fixes the highest‑risk issues first, without breaking existing public APIs, and with test coverage that allows incremental delivery.

## Decision

Implement a multi‑phase hardening plan that introduces safe subscription lifecycles, fiber‑aware request correlation, explicit adapter capabilities for structured outputs, deterministic prompt formatting, and clearer concurrency expectations. The work will be done in incremental phases that can ship independently.

## Phases (Incremental Delivery)

### Phase 0 — Baseline & Safety Nets (No Behavior Change)

1. Add minimal specs that reproduce the current risks and lock in current behavior:
   - Subscription lifecycle: create/destroy a module and assert the event registry drops the listener once the module is GC’d (or explicit teardown is called).
   - LM request correlation: concurrent fibers emit distinct `request_id`s for token events.
   - Structured outputs: ensure TOON `data_format` does not use JSON‑only structured prompts.
2. Document current behavior and edge cases in `adr/ARCHITECTURE.md` (short section), so future refactors have a baseline.
3. Add a tiny “compat matrix” note: which gems are impacted in each phase (core vs adapters vs o11y).

### Phase 1 — Subscription Lifecycle (Memory Leak Fix)

Goal: Ensure module-scoped listeners do not keep module instances alive.

Options considered:
- **WeakRef based callbacks (preferred):** store a weak reference to the module instance, and auto‑unsubscribe when dereferencing fails.
- Finalizers: risky for ordering, avoid unless necessary.
- Explicit `#close` only: relies on user discipline; insufficient alone.

Plan:
1. Add a `DSPy::Module` helper that subscribes using a `WeakRef` to `self` and closes over only the subscription id + weakref.
2. On callback invocation, if weakref is dead, auto‑unsubscribe and return.
3. Promote `unsubscribe_module_events` to a public method (or add `close` alias) for explicit cleanup in long‑running apps.
4. Add a small logging guard when auto‑unsubscribing (debug level) to aid tracing.
5. Spec: ensure a module can be GC’d after use and no listener fires for it thereafter.

Backward compatibility: no user-facing API break; existing `subscribe` DSL continues to work.

### Phase 2 — Fiber‑Aware Request Correlation

Goal: Avoid cross‑fiber contamination of request/timing metadata.

Plan:
1. Move request correlation fields into `DSPy::Context.current` (or a dedicated fiber-local store) instead of `Thread.current`.
2. Expose a small API (`Context.with_request` or similar) to set/reset request metadata in a scoped way.
3. Update `LM#execute_raw_chat` and `LM#emit_token_usage` to use the fiber‑local context.
4. Spec: concurrent fibers emit distinct `request_id`s and durations.

Backward compatibility: existing logging fields are preserved; only source of data changes.

### Phase 3A — Structured Outputs Capability Interface (Adapters First)

Goal: Remove coupling to adapter class names and instance variables; make structured outputs capability explicit and consistent.

Plan:
1. Introduce `supports_structured_outputs?` and `structured_outputs_enabled?` on `DSPy::LM::Adapter` (default false/true as appropriate).
2. Implement/override in each adapter (OpenAI/Gemini/Anthropic/RubyLLM/Ollama/OpenRouter).
3. Leave `LM#will_use_structured_outputs?` unchanged in this phase (no behavior change), but add a shim path for adapters to self‑report.

Backward compatibility: adapter interface is additive only.

### Phase 3B — Structured Outputs Routing (Core Behavior Change)

Plan:
1. Update `LM#will_use_structured_outputs?` to use adapter capability methods instead of class name checks / `instance_variable_get`.
2. Respect `data_format` in prompt selection: if `data_format == :toon`, avoid JSON‑only structured prompts or introduce TOON‑compatible structured prompt variant.
3. Spec: TOON data format never selects JSON‑only structured prompts.

Backward compatibility: existing adapters keep default behavior; failures become explicit capability misses rather than brittle reflection.

### Phase 4 — Deterministic Prompt Formats

Goal: A prompt’s schema/data format should not silently change due to global config mutations.

Plan:
1. Resolve `schema_format` and `data_format` at `Prompt` construction and avoid re‑reading `DSPy.config.lm` on render.
2. Add explicit `Prompt#with_schema_format` / `Prompt#with_data_format` to allow opt‑in changes.
3. Ensure `Predict` uses the LM from its own config (or fiber override) to seed prompt formats when created or reconfigured.

Backward compatibility: prompts continue to render as before unless global config changes at runtime; in that case behavior becomes stable instead of mutable.

### Phase 5 — Concurrency Safety & Documentation

Goal: Make concurrent evaluation safe and predictable.

Plan:
1. Add a `#fork`/`#dup_for_thread` pattern on `DSPy::Module` (or just `Predict`) to produce a deep‑copied predictor with independent mutable state.
2. Update `Evals` and `MIPROv2` to use per‑thread instances when running in parallel.
3. Document thread safety: explicit statement that modules are not thread‑safe unless forked.

Backward compatibility: default single‑thread usage unchanged; parallel evaluation becomes safer without forcing mutexes.

### Phase 6 — Dead Code Cleanup

Goal: Reduce maintenance burden by removing/isolating unused paths.

Plan:
1. Remove or deprecate unused fields/methods (`@subscription_counter`, `Prompt#to_messages`, `LM#validate_messages!`, etc.) after verifying no external usage.
2. Keep public methods only if needed by external API or docs; otherwise delete with a changelog note.

## Sequencing Rationale

- Phase 1 (subscriptions) is the highest‑risk leak and is isolated from other subsystems.
- Phase 2 (request correlation) is localized to LM/event emission and reduces incorrect metrics.
- Phase 3A/3B splits adapter interface changes from core routing changes to reduce cross‑gem risk.
- Phase 4 locks prompt format determinism after structured outputs routing is stabilized.
- Phase 5 clarifies thread safety and reduces cross‑talk in evaluation/optimization.
- Phase 6 cleans up once behavior is stable and covered by tests.

## Consequences

- Incremental adoption avoids a large, risky refactor.
- WeakRef‑based auto‑unsubscribe eliminates the most severe memory leak without changing the subscription DSL.
- Fiber‑aware request correlation fixes misattributed usage in concurrent `Async` workloads.
- Adapter capability interface makes structured outputs and prompt selection robust and extensible.
- Deterministic prompt formatting avoids subtle global‑config races.
- Parallel evals become safe via instance cloning rather than heavy locking.

## Open Questions

1. Do we want a strict “no implicit global config reads” policy across all prompt/LM code?
2. Should `DSPy::Module` provide a standardized `#close` hook or implement `AutoCloseable` semantics in the future?
3. Should TOON structured outputs be supported via native provider schema (if/when APIs support TOON), or should TOON bypass structured outputs entirely?

## Success Metrics

- Module instances become eligible for GC after going out of scope with no retained listeners.
- Token usage events in concurrent fibers report correct `request_id` and durations.
- Structured outputs selection no longer relies on class‑name checks or instance variable hacks.
- Parallel evals do not mutate shared predictor state.
