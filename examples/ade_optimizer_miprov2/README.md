# ADE MIPROv2 Optimization Demo

This example shows how to use DSPy.rb's MIPROv2 teleprompter to optimize prompts for an adverse drug event (ADE) classifier. It fetches a sample from the [ADE Corpus V2](https://huggingface.co/datasets/ade-benchmark-corpus/ade_corpus_v2) dataset, evaluates a baseline prompt, runs MIPROv2, and reports the improvement.

```bash
OPENAI_API_KEY=sk-... bundle exec ruby examples/ade_optimizer_miprov2/main.rb \
  --limit 200 \
  --auto light
```

Outputs (JSON, CSV, trial log JSON) are written under `examples/ade_optimizer_miprov2/results`. Dataset samples are cached under `examples/ade_optimizer_miprov2/data` and can be safely deleted to refresh the download.

## Options

| Flag | Description |
| --- | --- |
| `--limit` | Number of ADE examples to download (default: 300) |
| `--trials` | Manual override for MIPROv2 trial count (default: 6 when `--auto` is omitted) |
| `--auto` | Use a preset MIPROv2 configuration (`light`, `medium`, `heavy`) |
| `--seed` | Random seed for dataset splits (defaults to a random seed printed at runtime) |

## What it Does

1. Downloads classification rows from the ADE dataset via the Hugging Face dataset server.
2. Converts rows into `DSPy::Example`s for a simple `ADETextClassifier` signature.
3. Evaluates a baseline `DSPy::Predict` instance.
4. Runs `DSPy::Teleprompt::MIPROv2` with a small configuration to learn better instructions/demos.
5. Evaluates the optimized program and stores the results (malformed outputs now count toward errors, so 100% precision is no longer assumed).

The data split step keeps both ADE labels present in train/val/test when possible, ensuring validation metrics stay meaningful even with small sample sizes. The script prints the seed it used (helpful for reproducing a run) and the total optimization time so you can track throughput across experiments.

The script is designed for storytelling/framing purposes (“how models can write prompts for you”). Feel free to expand it with additional metrics, visualisation, or article-friendly commentary.
