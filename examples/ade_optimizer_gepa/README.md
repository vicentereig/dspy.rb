# ADE GEPA Optimization Demo

This example mirrors the MIPROv2 ADE optimizer, but uses `DSPy::Teleprompt::GEPA` with predictor-level feedback hooks. It downloads a subset of the Adverse Drug Event dataset, optimizes a simple classifier, and writes a summary plus metrics to the `results/` directory.

## Prerequisites

- Ruby 3.3 via `rbenv`
- Bundler dependencies installed (`bundle install`)
- `OPENAI_API_KEY` set in the environment (used for both student and reflection LMs)

## Run

```bash
bundle exec ruby examples/ade_optimizer_gepa/main.rb --limit 200 --max-metric-calls 48 --minibatch-size 6
```

Use `--help` to see all CLI options. Results and logs are stored under `examples/ade_optimizer_gepa/results/`.
