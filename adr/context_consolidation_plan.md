# Context Engineering consolidation plan

## Async & concurrency cluster
- `_articles/async-telemetry-optimization.md`, `_articles/concurrent-llm-processing-performance-gains.md`, `_articles/dspy-async-sidekiq-integration.md`, and `_articles/dspy-rb-concurrent-architecture-deep-dive.md` repeat the same “why async matters” story with overlapping diagrams and config snippets.
- Proposal: merge into a single “Async execution in production” hub that links out to Sidekiq configuration, telemetry hooks, and architectural deep dive sections; keep the most up-to-date benchmarks and drop redundant tables.
- Deliverables:
  - Canonical doc in `/production/` (or `/advanced/async/`) with provider-specific callouts.
  - Short article that summarizes results for marketing/blog, pointing back to the canonical guide.

## Persistence & registry overlap
- `_articles/program-persistence-and-serialization.md`, `production/storage.md`, and `production/registry.md` cover storage lifecycle, versioning, and deployment management with similar step-by-step walkthroughs.
- Proposal: create a single “Operational context” sequence: Storage → Registry → Deployment, move shared concepts (import/export, version metadata, history APIs) into shared partials, and trim the article down to a case study that references the canonical docs.

## Observability story
- `_articles/observability-in-action-langfuse.md` and `production/observability.md` both document Langfuse setup, event taxonomy, and telemetry outcomes.
- Proposal: keep `production/observability.md` as the source of truth; convert the article into a success-story landing page that links to the canonical guide and removes duplicate setup sections.

## Fiber-local LM guidance
- `_articles/fiber-local-lm-contexts.md` now overlaps with the new `core-concepts/module-runtime-context.md`.
- Proposal: update the article to point to the core guide for implementation details and retain only the motivation/announcement portions.
