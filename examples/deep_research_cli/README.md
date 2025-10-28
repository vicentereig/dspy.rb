# DSPy Deep Research CLI

This example packages the DeepSearch → DeepResearch workflow from [ADR 015](../../adr/015-deepsearch-deepresearch-implementation-plan.md) into an interactive terminal assistant. It is grounded in the orchestration work merged through PR #175 (“Implement DeepSearch & DeepResearch orchestration”) and Issue #163, and exercises the module-scoped events added during that effort.

## Highlights

- **Full agent loop** – Runs `DSPy::DeepResearch::Module` (planner → search → synthesis → QA) on each brief, backed by the Exa client and the model defaults defined in `lib/dspy/deep_search/module.rb` / `lib/dspy/deep_research/module.rb`.
- **Status board instrumentation** – `Examples::DeepResearchCLI::StatusBoard` subscribes to the same event stream documented in Issue #163 (`deep_search.*`, `deep_research.*`, `lm.tokens`) so you see live section progress, retry decisions, and elapsed time.
- **Accurate token metering** – The status board tallies `lm.tokens` events emitted by DeepSearch/DeepResearch. The integration spec `spec/integration/deep_research/module_spec.rb` (“retries sections when QA requests more evidence and accounts for additional tokens”) verifies the totals match the underlying module usage.
- **Memory-aware supervisor** – Requests flow through `DSPy::DeepResearchWithMemory`, which collects recent reports and replays them into subsequent calls. Its behaviour is covered by `spec/unit/examples/deep_research_cli/deep_research_with_memory_spec.rb`.
- **Budget-friendly failure mode** – If the inner DeepSearch hits `DSPy::DeepSearch::Module::TokenBudgetExceeded`, the CLI surfaces the warning and falls back to the in-memory transcript rather than crashing.
- **Dry-run fallback** – Pass `--dry-run` to exercise the CLI without touching external services. The stub module is defined alongside the production wiring in `examples/deep_research_cli/chat.rb`.

## Requirements

1. Install dependencies and ensure you are using the project Ruby version (the repo targets Ruby 3.4, see `.ruby-version`).
   ```bash
   rbenv install 3.4.5   # once
   bundle install
   ```
2. Create or update `.env` in the repository root with the credentials the agent needs:
   ```bash
   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=...          # optional fallback
   EXA_API_KEY=exa_dev_...
   DEEP_RESEARCH_MODEL=openai/gpt-4.1   # optional override
   ```
   The CLI loads `.env` via `Dotenv.load` (see `chat.rb:18`). Without an LLM key and `EXA_API_KEY`, the non‐dry run will exit early (`ensure_configuration!`).

## Running the CLI

```bash
rbenv exec bundle exec ruby examples/deep_research_cli/chat.rb
```

Interactive options:
- `--dry-run` — bypass real DeepSearch/DeepResearch and use the in-process stub (`DryRunDeepResearch`) for demos or CI.
- `--memory-limit=COUNT` — cap the number of transcripts retained by `DSPy::DeepResearchWithMemory` (defaults to 5).

While a brief is in flight, the status bar inside the `CLI::UI::Spinner` displays:

```
Status: Section Overview (attempt 1) | In: 541 Out: 1303 | Elapsed: 13s
```

The `StatusBoard` updates this label in response to:

- `deep_search.loop.started`, `deep_search.fetch.started`, `deep_search.fetch.completed`, `deep_search.fetch.failed`
- `deep_search.reason.decision`
- `deep_research.section.started`, `.qa_retry`, `.approved`, `.partial`, `.insufficient_evidence`
- `deep_research.report.ready`, `deep_research.memory.updated`
- `lm.tokens` (filtered to DeepSearch/DeepResearch modules via the module metadata added in Issue #163)

Completed runs render:

1. A summary frame with the brief, synthesized report, and citation rollup.
2. One `CLI::UI::Frame` per section, including citations.
3. A “Recent Memory” frame showing the rolling buffer maintained by `DSPy::DeepResearchWithMemory`.

If the token budget is exhausted mid-search, the CLI prints the warning and shows the memory buffer so you do not lose the collected evidence (mirrors the logic in `run_research` and the `DeepSearch` partial-result handling validated in `spec/unit/deep_search/module_spec.rb`).

## How this maps to the specs

- `spec/integration/deep_research/module_spec.rb`
  - `"aggregates DeepSearch runs into a coherent report"` exercises the Exa-backed flow recorded under `spec/vcr_cassettes/DSPy_DeepResearch_Module/`.
  - `"retries sections when QA requests more evidence and accounts for additional tokens"` drives the multi-attempt QA path that the status board visualises.
- `spec/unit/examples/deep_research_cli/deep_research_with_memory_spec.rb` locks down the memory supervisor hooks that the CLI uses.
- `spec/unit/deep_search/module_spec.rb` covers the budget exhaustion path that surfaces as the red warning in the CLI.

Run all relevant suites before shipping changes:

```bash
rbenv exec bundle exec rspec \
  spec/unit/deep_search/module_spec.rb \
  spec/integration/deep_search/module_spec.rb \
  spec/integration/deep_research/module_spec.rb \
  spec/unit/examples/deep_research_cli/deep_research_with_memory_spec.rb
```

## Observability tips

The CLI turns on the default DSPy observability pipeline (`DSPy::Observability.configure!`). If you have Langfuse credentials in `.env`, the emitted spans and `lm.tokens` events will mirror what you see in the `StatusBoard`. Combine this with the Langfuse trace tooling (`bundle exec lf traces ...`) to diagnose long-running searches or unexpected retries, as we did while analysing trace `e78c2f6918c4e1a95b80a423de7c537d`.

## Further reading

- ADR 015 – Phase breakdown and design constraints for DeepSearch/DeepResearch.
- Issue #163 – Background on module-scoped listeners and the event keys surfaced in the CLI.
- Jina AI’s “Practical Guide to Implementing DeepSearch & DeepResearch” – the architecture this example follows.
