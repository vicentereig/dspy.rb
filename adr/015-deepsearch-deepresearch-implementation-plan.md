# 015: DeepSearch & DeepResearch Implementation Plan

Date: 2025-10-27

## Status

In Progress (Phase 4)

## Context

We want to ship DeepSearch and DeepResearch as sibling gems that build on DSPy’s module-scoped listener architecture (Issue #163) and reuse the published `exa-ai-ruby` gem (Sorbet-typed transport, pooled Net::HTTP, streaming) for web search and content retrieval. The plan must support incremental delivery, commit early/often, and follow test-driven development with VCR-backed integration specs.

Reference diagrams (dependency + sequence) live in [Issue #163 comment #3452292277](https://github.com/vicentereig/dspy.rb/issues/163#issuecomment-3452292277); keep that comment in sync with ADR updates.

## Decision

We will tackle the work bottom-up, establishing guardrails with unit specs before wiring higher-level modules. The outline below serves as our running checklist; we will update this ADR as milestones are completed.

### Phase 0: Repository scaffolding ✅

1. ✅ Create `dspy-deepsearch` gem skeleton (gemspec, bundler setup, `lib/dspy/deep_search/version.rb`).
2. ✅ Configure shared dev dependencies (`rspec`, `vcr`, `sorbet-runtime`, `exa-ruby`) and CI templates.
3. ✅ Commit scaffolding immediately and open a draft PR to track progress.

### Phase 1: Core primitives (TDD) ✅

1. ✅ Write failing specs for `TokenBudget` and `GapQueue` utilities (per-run budget guard, FIFO queue semantics).
2. ✅ Implement the minimal classes with Sorbet signatures; ensure specs pass.
3. ✅ Add unit spec for module-scoped token listener integration once Issue #163 APIs land.

### Phase 2: Exa client adapter ✅

1. ✅ Wrap `Exa::Client` from the `exa-ai-ruby` gem with a thin adapter providing search + read entry points and typed errors.
2. ✅ Record VCR cassettes for success, empty SERP, and transport failure.
3. ✅ Write integration specs asserting retry/backoff behaviour and error propagation.

### Phase 3: DeepSearch module ✅ (Completed 2025-10-27)

1. ✅ Define DSPy signatures for seed query, search, read, and reason steps.
2. ✅ Add failing integration spec exercising the full loop against canned VCR responses, expecting an answer under budget with citations.
3. ✅ Implement the `DeepSearch` module: seed query dispatch, token metering, FIFO gap queue, budget enforcement.
4. ✅ Emit module-scoped events for telemetry, raising `TokenBudgetExceeded` when necessary.

### Phase 4: DeepResearch orchestrator (In Progress)

1. ✅ Create sibling gem `dspy-deep_research` (reuse tooling from Phase 0).
2. ✅ Planner signature spec outputs deterministic TOC/section goals (stub LLM).
3. ✅ Section queue orchestration spec ensures DeepSearch runs per section and requeues when QA flags gaps.
4. ✅ Implement coherence reviewer / QA module and error types (`EvidenceDeficitError`, `QueueStarvationError`, `SynthesisCoherenceError`).
5. ✅ Extend DeepResearch integration to cover multi-attempt QA feedback with tokenizer accounting (Phase 5 dependency).

### Phase 5: End-to-end integration

1. Record full workflow VCR cassette (brief → report).
2. Write spec asserting aggregated token usage equals sum of section runs and that QA can trigger additional DeepSearch cycles.
3. Document standard error flows and recovery strategies.

### Phase 6: Documentation & polish

1. Publish README updates in both gems with mermaid diagrams, setup instructions, and error-handling guides.
2. Add sample scripts using recorded cassettes for local testing.
3. Finalize PRs, update this ADR status to “Accepted”, and tag initial gem releases.

## Consequences

- Incremental commits and draft PR ensure visibility and early feedback.
- TDD with VCR cassettes guards against regressions when search providers change.
- Reusing `exa-ruby` reduces transport risk and keeps implementations consistent across projects.
