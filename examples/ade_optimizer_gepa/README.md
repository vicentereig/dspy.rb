# Run GEPA on the ADE Classifier

This example downloads an Adverse Drug Event dataset slice, evaluates a typed classifier, runs `DSPy::Teleprompt::GEPA`, evaluates the selected program, and writes metrics and run metadata.

## Prerequisites

- the repository's pinned Ruby 3.4.5 and Bundler
- `dspy-gepa` in the bundle (`DSPY_WITH_GEPA=1 rbenv exec bundle install` in this monorepo)
- a provider key for the selected model; the default is `openai/gpt-4o-mini`
- network access for the dataset download and provider calls

## Run

From the repository root:

```bash
export OPENAI_API_KEY="your-key"
rbenv exec bundle exec ruby examples/ade_optimizer_gepa/main.rb \
  --limit 30 \
  --max-metric-calls 600 \
  --minibatch-size 6
```

The script prints the baseline and optimized metrics. It writes a timestamped run beneath `examples/ade_optimizer_gepa/results/<provider>/<model>/`; `--track-stats` also writes GEPA event JSONL.

Use `--help` to inspect all flags. `--model provider/model` changes the provider and therefore the required `*_API_KEY` variable.

## Failure Conditions and Interpretation

- An invalid model ID or missing provider key stops before optimization.
- Dataset and provider requests require network access and may fail or be rate-limited.
- `--max-metric-calls` is a hard evaluation budget. The script raises a too-small budget enough to cover validation and minibatch work, so the effective value can exceed the argument.
- Scores depend on the split, model, metric, reflection budget, and run variance. Compare the selected program on held-out examples; do not treat one run as a general GEPA improvement claim.
