# Run the Deep Research CLI

This terminal example wraps `DSPy::DeepResearch::Module`, displays section and token events, and retains a bounded in-memory history of recent reports.

## Prerequisites

- the repository's pinned Ruby and installed bundle
- for a real run, `EXA_API_KEY` plus a key for the model selected by `DEEP_RESEARCH_MODEL`
- provider and search network access

The CLI loads `.env` from the repository root. Its default model is `openai/gpt-4.1`; set `DEEP_RESEARCH_MODEL` to a fully qualified model available through an installed adapter.

## Run Without External Calls

```bash
rbenv exec bundle exec ruby examples/deep_research_cli/chat.rb --dry-run
```

Dry-run mode uses an in-process stub. It opens the interactive CLI and renders result and recent-memory frames without calling a provider or Exa.

## Run DeepResearch

```bash
export EXA_API_KEY="your-exa-key"
export OPENAI_API_KEY="your-model-provider-key"
export DEEP_RESEARCH_MODEL="openai/gpt-4.1"
rbenv exec bundle exec ruby examples/deep_research_cli/chat.rb
```

Enter a research brief at the prompt. A completed run renders the assembled report, section results, citations, warnings, and recent-memory frame. `--memory-limit=COUNT` changes the number of transcripts retained in memory.

## Failure Conditions and Boundaries

- A real run exits early when `EXA_API_KEY` or the model provider key is missing.
- Provider, search, rate-limit, and token-budget failures can produce warnings, partial sections, or insufficient-evidence results.
- The memory buffer is process-local and not durable storage.
- Collected URLs and generated citations require review. The CLI does not establish source authority or report correctness.
