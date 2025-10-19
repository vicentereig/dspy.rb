# ADE GEPA Optimization Demo

This example mirrors the MIPROv2 ADE optimizer, but uses `DSPy::Teleprompt::GEPA` with predictor-level feedback hooks. It downloads a subset of the Adverse Drug Event dataset, optimizes a simple classifier, and writes a summary plus metrics to the `results/` directory.

## Prerequisites

- Ruby 3.3 via `rbenv`
- Bundler dependencies installed (`bundle install`)
- `OPENAI_API_KEY` set in the environment (used for both student and reflection LMs)

## Run

```bash
bundle exec ruby examples/ade_optimizer_gepa/main.rb --limit 30 --max-metric-calls 600 --minibatch-size 6
```

> **Notes:**
> - GEPA starts from the default DSPy prompt; improvements depend on the dataset split and reflection budget.
> - Ensure `--max-metric-calls` exceeds the validation set size (plus a couple of minibatches). The script auto-adjusts upward if the budget is too small.

Use `--help` to see all CLI options. Results and logs are stored under `examples/ade_optimizer_gepa/results/`.
