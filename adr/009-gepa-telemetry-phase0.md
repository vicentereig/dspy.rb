# ADR 009: GEPA Telemetry Phase 0 Plan

## Status
Proposed

## Context
- Issue: [#107](https://github.com/vicentereig/dspy.rb/issues/107)
- Goal: Port the Python GEPA optimizer to Ruby with full observability parity.
- Reference materials:
  - Sequence diagrams outlined in the GitHub issue (GEPA optimize → Engine → Proposer flow).
  - Existing Ruby instrumentation for `DSPy::Teleprompt::MIPROv2`.
  - Python OpenTelemetry hooks in `../gepa` and `../dspy`.

The GEPA optimization flow introduces several long-running phases with nested loops:

1. `GEPA.optimize` bootstraps state, evaluates the seed candidate, and delegates to `GEPAEngine.run`.
2. `GEPAEngine` performs iterative reflective mutation:
   - Select a Pareto candidate.
   - Sample minibatches and evaluate the current program.
   - Assemble reflective datasets from traces.
   - Ask the reflection LM for new instructions.
   - Evaluate / accept the new candidate and update Pareto fronts.

Each of these steps maps cleanly to observability spans in the existing Python implementation (via Langfuse / OpenTelemetry). To maintain parity, we need a dedicated telemetry layer before writing the full port so that subsequent phases can instrument logic as it lands.

## Decision
Add a reusable `GEPA::Telemetry` module that standardizes span names, attributes, and logging events for every stage of the sequence diagram. Phase 0 will deliver:

1. **Telemetry primitives**
   - `GEPA::Telemetry.with_span(operation, metadata = {}, &block)` → wraps `DSPy::Context.with_span`, injects GEPA metadata, and mirrors Python span names (`gepa.optimize`, `gepa.engine.iteration`, etc.).
   - `GEPA::Telemetry.emit(event, metadata = {})` → thin wrapper over `DSPy.log` for structured logs when OTEL is disabled.
   - Default attributes include `optimizer: "GEPA"`, optional iteration counters, candidate IDs, and LM request hashes.

2. **Span naming map** derived from the sequence diagram:
   | Ruby span key | Python / diagram step |
   | ------------- | --------------------- |
   | `gepa.optimize` | API entry span |
   | `gepa.state.initialize` | seed candidate + baseline |
   | `gepa.engine.run` | outer optimization loop |
   | `gepa.engine.iteration` | per-iteration boundary |
   | `gepa.proposer.select_candidate` | Pareto selection |
   | `gepa.proposer.evaluate_subsample` | minibatch evaluation w/ traces |
   | `gepa.proposer.make_reflective_dataset` | dataset building |
   | `gepa.proposer.generate_candidate` | LM reflection round |
   | `gepa.engine.acceptance_test` | validation + Pareto update |

3. **Spec scaffolding**
   - `spec/unit/gepa/telemetry_spec.rb` ensures spans set expected attributes and preserve parent/child relationships when nesting.
   - Use `DSPy::Observability.enabled?` guard to validate behaviour both with and without OTEL.

4. **Developer documentation**
   - Document Phase 0 plan for future contributors (this ADR).
   - Provide usage examples showing how later phases (engine, proposer, adapter) will call the helpers.

## Consequences
- Later implementation phases can focus on business logic while calling `GEPA::Telemetry` helpers to emit spans.
- Ensures parity with Python observability before logic lands, reducing risk of missing instrumentation.
- Introducing telemetry first allows us to write tests that assert span names/attributes even if the optimizer logic is still a stub.

## Phase 0 Deliverables Checklist
- [ ] `GEPA::Telemetry` module plus helpers.
- [ ] Unit tests covering nested span behaviour and attribute propagation.
- [ ] Placeholder `spec/fixtures/gepa/telemetry_events.yml` (if needed) to validate logging output.
- [ ] Documentation updates (this ADR referenced from CHANGELOG once merged).

