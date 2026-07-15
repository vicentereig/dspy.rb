---
layout: docs
title: "MIPROv2 Program Optimization in Ruby"
name: MIPROv2 Optimizer
description: "Use the ADE example to configure MIPROv2, define a metric, set a search budget, and inspect the optimized program."
date: 2025-07-10 00:00:00 +0000
---
# MIPROv2 Optimizer

See the [package and capability matrix](/dspy.rb/getting-started/packages/) for the `dspy-miprov2` install, require, dependency, and support boundary.

MIPROv2 searches over instructions and few-shot demonstrations for one or more predictors. You provide a typed program, examples, a metric, and a budget. It evaluates candidates on minibatches and returns the best program it found for the validation data.[^miprov2-paper]

## Decide Whether MIPROv2 Fits

- **Metric-driven**: Candidate selection follows the metric you provide.
- **Program-aware**: Multi-stage predictors (e.g., ReAct agents) receive separate instructions, so improvements land where they matter.
- **Data-aware**: The optimizer bootstraps few-shot demos and dataset summaries before proposing instructions, keeping candidates grounded in your examples.
- **Budgeted**: Trial and minibatch settings bound the search work.

> ℹ️ **Packaging note** — MIPROv2 ships as the `dspy-miprov2` gem. Add it alongside `dspy` in your `Gemfile`:
> ```ruby
> gem "dspy"
> gem "dspy-miprov2"
> ```
> Bundler will require `dspy/miprov2` automatically. The separate gem keeps the Gaussian Process dependency tree out of apps that do not need advanced optimization.

## Quickstart (ADE demo)

Run the repository's ADE demo to inspect one bounded MIPROv2 workflow:

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
- A JSON dump of the trial logs for inspecting candidate changes in your application.

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

Hold back a test set from the optimization loop. MIPROv2 selects candidates on train and validation data; compare the selected program on held-out or production data before making a generalization claim.

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
| `light` | 6 | Small datasets or prototypes with a six-trial budget. |
| `medium` | 12 | More candidate exploration when twelve trials fit the runtime budget. |
| `heavy` | 18 | Multi-stage programs that justify an eighteen-trial budget. |

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

- `optimized_program` — `DSPy::Predict` with the selected instruction and demonstrations; evaluate it before use.
- `optimization_trace[:trial_logs]` — per-trial record of instructions, demos, and scores.
- `metadata[:optimizer]` — `"MIPROv2"`, useful when you persist experiments from multiple optimizers.

## Reading the outputs

MIPROv2 writes two main artifacts under `examples/ade_optimizer_miprov2/results/`:

- `summary.json` — baseline vs. optimized metrics, trial budget, elapsed time, random seed.
- `metrics.csv` — accuracy, precision, recall, and F1 per run (easy to plot or import into spreadsheets).

Inside the console you’ll also see the best instruction found during the run. To persist the complete optimized program, store it with the optimization result:

```ruby
storage = DSPy::Storage::ProgramStorage.new(
  storage_path: "./dspy_storage"
)

saved = storage.save_program(
  result.optimized_program,
  result,
  metadata: { dataset: "ade-v1" }
)

loaded = storage.load_program(saved.program_id)
loaded_program = loaded.program
```

The program and signature classes must be loaded when you restore the artifact, and the program class must implement `.from_h`. Evaluate `loaded_program` against the held-out set before promoting it.

## Fits multi-stage programs too

The ADE demo has one predictor. For a multi-predictor example, see `spec/integration/dspy/mipro_v2_re_act_integration_spec.rb`, where the optimizer:

- Generates dataset summaries for each predictor.
- Proposes per-stage instructions for a ReAct agent (`thought_generator`, `observation_processor`).
- Tracks which predictor benefited the most, so you can spot bottlenecks.

If your pipeline mixes tools and plain LLM calls, the metric sees only the final output—the optimizer handles credit assignment internally.

## Field notes from the MIPRO paper

The Stanford team behind MIPROv2 observed three practices that translate well to Ruby apps[^miprov2-paper]:

1. **Ground proposals in real data** — They seed candidates with dataset summaries and bootstrap few-shot examples. DSPy.rb's implementation does this through `DatasetSummaryGenerator` and the bootstrap phase, so the quality of the examples matters.
2. **Stochastic evaluation keeps the loop affordable** — Mini-batching during evaluation mimics a noisy but cheaper fitness function. Use the presets’ defaults unless you have a strict budget; then lower `minibatch_size` to stretch API calls.
3. **Proposal strategy adapts within a run** — MIPROv2 changes which proposal strategies it favors based on earlier trial results. Inspect the completed trial log rather than inferring behavior from an early candidate.

The paper reports improvements on its evaluated tasks. Measure the Ruby program on a held-out set before promoting an optimized artifact.

## Gate Promotion on Held-Out Evidence

- Add both `dspy` and `dspy-miprov2` to the Gemfile.
- Keep validation and held-out test sets separate.
- Record `result.optimization_trace`, model identifiers, data version, and random seed.
- Serialize `result.optimized_program` and evaluate the loaded artifact before deployment.
- Re-run evaluation when the model, metric, or input distribution changes.

[^miprov2-paper]: Opsahl-Ong, Krista, et al. *Optimizing Instructions and Demonstrations for Multi-Stage Language Model Programs.* arXiv:2406.11695v2, 2024.
