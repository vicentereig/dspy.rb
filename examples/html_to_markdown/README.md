# Compare Typed AST and String HTML Conversion

This experiment sends the same sample HTML through two predictors: one returns a typed Markdown AST that Ruby renders, and one returns a Markdown string directly. It prints both results and a structural comparison.

## Prerequisites

- a repository checkout with `bundle install` completed
- `ANTHROPIC_API_KEY`
- access to the Anthropic model configured in `main.rb`

The script loads `.env` through `dotenv/load` and makes two provider calls.

## Run

From the repository root:

```bash
export ANTHROPIC_API_KEY="your-key"
bundle exec ruby examples/html_to_markdown/main.rb
```

The command prints the source HTML, each Markdown result, elapsed time, AST node count, output length, and counts for selected Markdown elements. It does not compute a semantic quality score.

Run the repository specs without a live provider request:

```bash
bundle exec rspec spec/examples/html_to_markdown_spec.rb
```

## Interpret the Result

The AST path adds runtime shape validation and deterministic rendering. The direct path uses fewer application types. Either path can omit or alter source meaning, so compare outputs against task-specific examples rather than choosing from one sample or token count.

## Failure Conditions

- A missing key raises before the first request.
- Provider, model, schema, extraction, or prediction-conversion errors can stop either path.
- Recursive-schema and structured-output support varies by provider, model, and SDK version. This script exercises its configured Anthropic prompt-based path; it does not prove support across all providers.
