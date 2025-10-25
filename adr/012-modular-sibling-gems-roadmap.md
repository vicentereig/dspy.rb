# ADR 012: Modular Sibling Gems Roadmap

## Status
Proposed

## Context
- DSPy.rb currently bundles GEPA, MIPROv2, JSON-schema conversion, and Langfuse observability directly inside the core gem.
- Optional gems already exist for some subsystems (`dspy-miprov2`, `gepa`), but the code layout under `lib/dspy/**` does not reflect those boundaries. Consumers have to load everything even when they only need the core runtime.
- We need lighter installs for downstream projects (e.g., `exa-ruby` reusing Sorbet→JSON-schema without teleprompters) and a clearer path to future adapters (`dspy-o11y-newrelic`).
- This ADR records the goal of breaking DSPy.rb into sibling gems and the plan for executing the work incrementally.

## Decision
Adopt a phased roadmap that extracts tightly scoped, opt-in gems while keeping backwards-compatible shims in the main repo:

1. **dspy-gepa**
   - Move `DSPy::Teleprompt::GEPA`, its `PredictAdapter`, experiment tracker, telemetry helpers (ADR-009), and specs into a new gem that depends on both `dspy` and `gepa`.
   - Introduce `DSPY_WITH_GEPA` gating in the `Gemfile` identical to `DSPY_WITH_MIPROV2`.
   - Keep a thin shim under `lib/dspy/teleprompt/gepa.rb` that raises a helpful error if the gem is missing.

2. **dspy-miprov2 layout cleanup**
   - Relocate the teleprompter, auto modes, and Gaussian Process backend under `lib/dspy/mipro_v2/` inside the existing optional gem.
   - Leave shared bootstrapping helpers (InstructionUpdates, Utils, DataHandler) in the core gem because GEPA and future optimizers rely on them.

3. **dspy-json-schema**
   - Extract `DSPy::TypeSystem::SorbetJsonSchema` into an independent gem with only `sorbet-runtime` dependency.
   - Have `lib/dspy/type_system/sorbet_json_schema.rb` require the new gem and re-export the module to avoid breaking existing requires.
   - Document reuse guidance for `exa-ruby` in `docs/` once packaged.

4. **dspy-o11y & adapters**
   - Create a core observability gem (`dspy-o11y`) that provides `DSPy::Observability`, `AsyncSpanProcessor`, `ObservationType`, and the span/context hooks.
   - Build adapter gems that register exporters:
     - `dspy-o11y-langfuse` (extract current OTLP/Langfuse logic, env var config, and specs).
     - `dspy-o11y-newrelic` (future) to integrate `newrelic_rpm`.
   - Core DSPy should run even when no adapter is installed (no-op spans).

5. **Documentation & CI**
   - Update contributor-facing docs so the modular layout is obvious:
     - `README.md` (optional bundles section already listing `dspy-code_act`, `dspy-datasets`, `dspy-evals`, `dspy-miprov2`, `gepa`).
     - `docs/src/production/observability.md`, `docs/src/_articles/observability-in-action-langfuse.md`, and `docs/src/_articles/dspy-rb-concurrent-architecture-deep-dive.md` for observability adapters.
     - Optimization guides and examples (`docs/src/optimization/evaluation.md`, `docs/src/core-concepts/modules.md`, `examples/**`) for GEPA/MIPROv2 packaging notes.
     - ADR-ARCHITECTURE.md, ADR-010, CLAUDE.md, and any onboarding docs that explain current sibling gems.
   - Expand CI matrix to run with/without each optional gem to ensure shims work and load order stays deterministic.

## Consequences
- Installing `dspy` alone becomes lighter (no Langfuse/OpenTelemetry code or GEPA dependencies unless requested).
- Downstream projects can depend on specific functionality (e.g., JSON schema conversion) without pulling the entire stack.
- Maintainers need to version and release several gems in lockstep; automation (e.g., shared version constants) becomes more important.
- Testing must cover combinations of optional gems, increasing matrix complexity, and documentation changes become part of each extraction PR to keep parity references accurate.

## Next Steps
1. Review existing gemspecs (ADR-010) and ensure they can be reused as templates for the new packages.
2. Draft compatibility shims inside `lib/dspy/teleprompt` and `lib/dspy/type_system` before moving files, so short-lived PRs do not break main.
3. Update the `Gemfile`, `README`, and docs once each gem extraction lands.
4. Extend the GitHub Actions pipeline (building on ADR-011) with additional jobs that toggle `DSPY_WITH_*` flags and install new gems (`dspy-gepa`, `dspy-json-schema`, `dspy-o11y-*`) to verify lazy loading behavior across combinations.
