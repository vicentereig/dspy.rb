# Run MIPROv2 on the ADE Classifier

This example downloads an Adverse Drug Event dataset slice, evaluates a typed classifier, runs `DSPy::Teleprompt::MIPROv2`, evaluates the selected program, and writes the run artifacts.

## Prerequisites

- the repository's pinned Ruby and Bundler
- MIPROv2 and its numerical dependencies (`DSPY_WITH_MIPROV2=1 rbenv exec bundle install` in this monorepo)
- a provider key for the selected model; the default is `openai/gpt-5-2025-08-07`
- network access for the dataset download and provider calls

## Run

From the repository root:

```bash
export OPENAI_API_KEY="your-key"
rbenv exec bundle exec ruby examples/ade_optimizer_miprov2/main.rb \
  --limit 200 \
  --auto light \
  --seed 123
```

The script prints baseline and optimized ADE metrics, the seed, elapsed time, and artifact paths. JSON, CSV, and trial logs are written under `examples/ade_optimizer_miprov2/results/`; downloaded data is cached under `examples/ade_optimizer_miprov2/data/`.

Use `--help` for all options. `--auto` accepts `light`, `medium`, `heavy`, or `none`; `--trials` sets a manual trial count when an automatic preset is not used.

## Failure Conditions and Interpretation

- A missing key, invalid `provider/model` ID, unavailable model, or missing numerical dependency stops the run.
- Dataset and provider calls require network access and can be rate-limited or charged.
- Small limits may make class-balanced train, validation, and test splits impossible.
- Optimization searches against the supplied metric and validation set. Compare the selected program with the baseline on the held-out test split; one run does not establish general improvement.
