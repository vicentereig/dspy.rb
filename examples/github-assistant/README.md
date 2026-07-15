# Run the Read-Only GitHub Assistant

This example gives a bounded `DSPy::ReAct` agent the repository's read-only GitHub CLI Toolset. It can inspect repositories, issues, pull requests, and GET-only API routes; it does not expose create, update, or delete tools.

## Prerequisites

- a repository checkout with `bundle install` completed
- the GitHub CLI installed and authenticated (`gh auth login`)
- `OPENAI_API_KEY`; the script constructs `openai/gpt-4o-mini`
- network access to OpenAI and GitHub

The script loads `.env` from the repository root. An Anthropic key alone is not sufficient because the current example selects an OpenAI model.

## Run

Demo mode runs several predefined live queries:

```bash
bundle exec ruby examples/github-assistant/github_assistant.rb demo
```

Interactive mode accepts one task at a time:

```bash
bundle exec ruby examples/github-assistant/github_assistant.rb interactive
```

The script prints the available tools, the model's result, and any reported actions. Results vary with live repository data and model decisions.

## Read-Only Boundary

The Toolset exposes list, search, detail, and GET operations. The model cannot select a GitHub mutation through these declared tools. The underlying `gh` credential may still have broader account permissions, so keep its scope narrow and do not treat this example as a general shell sandbox.

## Failure Conditions

- The script exits when `gh` is missing, authentication fails, or `OPENAI_API_KEY` is absent.
- Missing repositories, insufficient GitHub permissions, rate limits, provider errors, and the 15-iteration bound can produce incomplete results.
- A model summary is not a substitute for inspecting the returned issue, pull request, or API data before acting on it.
