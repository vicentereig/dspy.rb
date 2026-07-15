# DSPy::DeepResearch

`dspy-deep_research` plans sections, runs `DSPy::DeepSearch` for evidence, reviews section drafts, and assembles a report. The package installs an exactly matched `dspy-deep_search` release.

See the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for canonical status, dependency, and file-overlap disclosures.

## Prerequisites

- Use the repository Ruby and Bundler versions for a checkout run.
- Dry-run mode needs no provider or Exa credential.
- A real run needs `EXA_API_KEY`, a configured DSPy.rb provider adapter, and that provider's credential.

## Run the Repository Example

From a repository checkout:

```bash
bundle install
bundle exec ruby examples/deep_research_cli/chat.rb --dry-run
```

Dry-run mode uses an in-process stub and makes no provider or Exa request. It opens the terminal interface and shows the result and memory frames.

For a real run, set `EXA_API_KEY`, a provider key, and optionally `DEEP_RESEARCH_MODEL`, then omit `--dry-run`:

```bash
export EXA_API_KEY="your-exa-key"
export OPENAI_API_KEY="your-model-provider-key"
export DEEP_RESEARCH_MODEL="openai/your-model-id"
bundle exec ruby examples/deep_research_cli/chat.rb
```

For application installation, add `gem "dspy-deep_research"`, require `dspy/deep_research`, and configure the provider adapters used by the planner, search, synthesis, QA, and report modules.

## Result and Failure Conditions

A run returns a report, section results, citations, warnings, and a `budget_exhausted` flag. Sections can be complete, partial, or marked as insufficient evidence.

- A real run exits early without the required model and Exa credentials.
- Provider, model, search quality, token budgets, section retries, and citation review remain application concerns.
- A generated citation is collected evidence, not proof that the source supports every sentence in the report. Review reports before publishing or acting on them.
