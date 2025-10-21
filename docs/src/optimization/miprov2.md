---
layout: docs
title: "MIPROv2 Ruby: Production-Ready Prompt Optimization"
name: MIPROv2 Optimizer
description: "Ship better multi-stage prompts by reusing the ADE MIPROv2 demo. Learn how to install the separate gem, plug in your metric, and let MIPROv2 iterate toward measurable wins."
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: MIPROv2 Optimizer
  url: "/optimization/miprov2/"
prev:
  name: GEPA Optimizer
  url: "/optimization/gepa/"
next:
  name: Evaluation
  url: "/optimization/evaluation/"
date: 2025-07-10 00:00:00 +0000
---
# MIPROv2 Optimizer

MIPROv2 is DSPy’s most capable instruction tuner. It was designed for language-model programs with multiple predictors, and focuses on outcomes: higher downstream accuracy, fewer hallucinations, and reusable prompt assets. Instead of tinkering with strings, you give MIPROv2 a typed program, a dataset, and a metric. The optimizer proposes new instructions and few-shot demonstrations, evaluates them on mini-batches, and keeps what actually moves your metric[^miprov2-paper].

Ruby developers care because the workflow stays familiar: typed signatures, `DSPy::Example` objects, and plain-old Ruby lambdas for metrics. MIPROv2 handles the heavy lifting—dataset summaries, per-predictor instructions, Bayesian search—without asking you to babysit the loop.

## Why teams reach for MIPROv2

- **Outcome-driven**: Every trial is accepted or rejected based on your metric (accuracy, recall, goal completion, etc.). No guesswork.
- **Program-aware**: Multi-stage predictors (e.g., ReAct agents) receive separate instructions, so improvements land where they matter.
- **Data-aware**: The optimizer bootstraps few-shot demos and dataset summaries before proposing instructions, keeping candidates grounded in your examples.
- **Budget friendly**: Mini-batch evaluations let you cap API spend. Presets expose trade-offs between speed and peak quality.

> ℹ️ **Packaging note** — MIPROv2 ships as the `dspy-miprov2` gem. Add it alongside `dspy` in your `Gemfile`:
> ```ruby
> gem "dspy"
> gem "dspy-miprov2"
> ```
> Bundler will require `dspy/miprov2` automatically. The separate gem keeps the Gaussian Process dependency tree out of apps that do not need advanced optimization.

## Quickstart (ADE demo)

The fastest way to see MIPROv2 is to run the ADE demo that lives in this repository:

```bash
bundle exec ruby examples/ade_optimizer_miprov2/main.rb \
  --limit 300 \
  --auto light \
  --seed 42
```

What you get out of a single command:

- Baseline accuracy/precision/recall/F1 for the typed ADE classifier.
- Six optimization trials (via the `light` preset) with per-trial instruction snapshots.
- Test-set metrics for the best candidate and a saved summary under `examples/ade_optimizer_miprov2/results/`.
- A JSON dump of the trial logs, handy for replaying improvements inside your own app.

Treat the demo as a recipe. Replace the dataset builder and metric with your own code, keep the rest.

## Integration walkthrough

Follow the structure from `examples/ade_optimizer_miprov2/main.rb` when bringing MIPROv2 into your project.

### 1. Describe the task with a signature

```ruby
class ADETextClassifier < DSPy::Signature
  description "Detect whether a clinical sentence mentions an adverse drug event."

  class ADELabel < T::Enum
    enums do
      Positive = new("1")
      Negative = new("0")
    end
  end

  input do
    const :text, String
  end

  output do
    const :label, ADELabel
  end
end

baseline_program = DSPy::Predict.new(ADETextClassifier)
```

Typed signatures give MIPROv2 the schema it needs for generating examples, validating LM outputs, and rendering prompts.

### 2. Build examples and measure a baseline

```ruby
examples = ADEExample.build_examples(rows) # converts rows into DSPy::Example
train, val, test = ADEExample.split_examples(examples, train_ratio: 0.6, val_ratio: 0.2, seed: seed)

baseline_metrics = ADEExample.evaluate(baseline_program, test)
puts "Baseline accuracy: #{(baseline_metrics.accuracy * 100).round(2)}%"
```

Hold back a test set from the optimization loop. MIPROv2 optimizes on train/val, but only your own test (or prod) data proves it generalized.

### 3. Define a developer-friendly metric

Metrics can be as simple as a boolean. The ADE demo shows the minimal viable option:

```ruby
metric = proc do |example, prediction|
  expected  = example.expected_values[:label]
  predicted = ADEExample.label_from_prediction(prediction)
  predicted == expected
end
```

Return `true` when the prediction meets your acceptance criteria. For richer feedback (e.g., correctness + penalty scores), return a numeric score or `DSPy::Prediction`.

### 4. Pick the right preset (or customize)

```ruby
optimizer =
  if preset
    DSPy::Teleprompt::MIPROv2.new(metric: metric).tap do |opt|
      opt.configure { |config| config.auto_preset = DSPy::Teleprompt::AutoPreset.deserialize(preset) }
    end
  else
    DSPy::Teleprompt::MIPROv2.new(metric: metric).tap do |opt|
      opt.configure do |config|
        config.num_trials = 6
        config.num_instruction_candidates = 3
        config.bootstrap_sets = 2
        config.max_bootstrapped_examples = 2
        config.max_labeled_examples = 4
        config.optimization_strategy = :adaptive
      end
    end
  end
```

Presets follow the paper’s guidance on how many trials, instruction candidates, and bootstrap batches you need:

| Preset | Trials | When to use |
| --- | --- | --- |
| `light` | 6 | Quick wins on small datasets or during prototyping. |
| `medium` | 12 | Balanced exploration vs. runtime for most production pilots. |
| `heavy` | 18 | Highest accuracy targets or multi-stage programs with several predictors. |

Switch to manual configuration when you already know the budget you can afford.

### 5. Compile and inspect the optimized program

```ruby
result = optimizer.compile(
  baseline_program,
  trainset: train,
  valset: val
)

optimized_program = result.optimized_program
optimized_metrics = ADEExample.evaluate(optimized_program, test)

puts "Accuracy gained: #{((optimized_metrics.accuracy - baseline_metrics.accuracy) * 100).round(2)} points"
```

The `result` object exposes:

- `optimized_program` — ready-to-use `DSPy::Predict` with new instruction and demos.
- `optimization_trace[:trial_logs]` — per-trial record of instructions, demos, and scores.
- `metadata[:optimizer]` — `"MIPROv2"`, useful when you persist experiments from multiple optimizers.

## Reading the outputs

MIPROv2 writes two main artifacts under `examples/ade_optimizer_miprov2/results/`:

- `summary.json` — baseline vs. optimized metrics, trial budget, elapsed time, random seed.
- `metrics.csv` — accuracy, precision, recall, and F1 per run (easy to plot or import into spreadsheets).

Inside the console you’ll also see a best-in-class instruction snippet. Paste it into your production prompt, or serialize the `optimized_program` with `DSPy::Serializer` and check it into Git.

## Fits multi-stage programs too

The ADE demo has a single predictor, but MIPROv2 shines when you have chains. See `spec/integration/dspy/mipro_v2_re_act_integration_spec.rb` for how the optimizer:

- Generates dataset summaries for each predictor.
- Proposes per-stage instructions for a ReAct agent (`thought_generator`, `observation_processor`).
- Tracks which predictor benefited the most, so you can spot bottlenecks.

If your pipeline mixes tools and plain LLM calls, the metric sees only the final output—the optimizer handles credit assignment internally.

## Field notes from the MIPRO paper

The Stanford team behind MIPROv2 observed three practices that translate well to Ruby apps[^miprov2-paper]:

1. **Ground proposals in real data** — They seed candidates with dataset summaries and bootstrap few-shot examples. In our Ruby port, this happens automatically via `DatasetSummaryGenerator` and the bootstrap phase, so give the optimizer clean examples and it will stay truthful.
2. **Stochastic evaluation keeps the loop affordable** — Mini-batching during evaluation mimics a noisy but cheaper fitness function. Use the presets’ defaults unless you have a strict budget; then lower `minibatch_size` to stretch API calls.
3. **Meta-learning improves over time** — MIPROv2 adjusts which proposal strategies to favor based on past wins. You only see the payoff (better instructions, fewer useless trials), so let multi-trial runs finish before judging the outcome.

The result: teams reported accuracy bumps of up to 13% on multi-hop QA tasks without touching model weights—just better prompts.

## Production checklist

- ✅ Add both `dspy` and `dspy-miprov2` to your Gemfile and bundle install.
- ✅ Keep a validation set separate from your test or staging traffic.
- ✅ Log `result.optimization_trace[:trial_logs]` so you can reproduce or audit changes.
- ✅ Promote the optimized program by serializing it to JSON/YAML and loading it in production.
- ✅ Re-run MIPROv2 when metrics drift or you add new training data.

With that, you can ship prompt improvements using the same Ruby tooling you already know—no manual prompt juggling required.

[^miprov2-paper]: Opsahl-Ong, Krista, et al. *Optimizing Instructions and Demonstrations for Multi-Stage Language Model Programs.* arXiv:2406.11695v2, 2024.
