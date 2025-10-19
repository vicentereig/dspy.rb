---
layout: docs
title: "GEPA Ruby: Reflective Prompt Evolution in Practice"
name: GEPA Optimizer
description: "Learn how to optimize Ruby predictors with GEPA, configure reflection feedback, and ship production-ready prompts using the ADE GEPA demo as your guide."
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: GEPA Optimizer
  url: "/optimization/gepa/"
prev:
  name: Prompt Optimization
  url: "/optimization/prompt-optimization/"
next:
  name: MIPROv2 Optimizer
  url: "/optimization/miprov2/"
date: 2025-07-10 00:00:00 +0000
---
# GEPA Optimizer

GEPA (Genetic-Pareto Reflective Prompt Evolution) continuously improves a DSPy program by replaying real traces, collecting feedback, and asking a reflection model to rewrite instructions. While MIPROv2 focuses on fast instruction search, GEPA shines when you have human-style feedback hooks or want to evolve prompts over longer horizons.

This guide walks through the production recipe used in `examples/ade_optimizer_gepa/`, then shows how to adapt it to your own signatures.

## Overview

GEPA runs in iterative loops:

- **Replay traces** collected during minibatch evaluation.
- **Summarize feedback** from your metric and optional predictor-level hooks.
- **Ask the reflection LM** to propose an improved instruction.
- **Accept or reject** the new candidate using Pareto dominance on score and novelty.

The Ruby port ships with telemetry, merge proposers, and experiment tracking out of the box. You only need to provide three inputs: a DSPy module, a metric that returns `DSPy::Prediction`, and an optional `feedback_map`.

## Quickstart (ADE demo)

The ADE demo optimizes a clinical text classifier with GEPA. Run it end-to-end:

```bash
bundle exec ruby examples/ade_optimizer_gepa/main.rb \
  --limit 30 \
  --max-metric-calls 600 \
  --minibatch-size 6
```

- Uses `DSPy::Teleprompt::GEPA` with a reflective OpenAI LM.
- Downloads a small ADE dataset, splits into train/val/test, and logs results under `examples/ade_optimizer_gepa/results/`.
- Auto-adjusts `max_metric_calls` to cover validation if your budget is too low.

Once you have the basics running, lift the same structure into your application.

## Step-by-step Integration

### 1. Define the signature and baseline program

```ruby
class ADETextClassifier < DSPy::Signature
  description "Determine if a clinical sentence describes an adverse drug event"

  input do
    const :text, String
  end

  output do
    const :label, ADELabel
  end
end

program = DSPy::Predict.new(ADETextClassifier)
```

Start from a vanilla `DSPy::Predict` so you have an instruction to evolve and a prompt container for few-shot examples.

### 2. Build datasets and evaluation helpers

The demo converts ADE rows into strongly typed `DSPy::Example` instances and provides an `evaluate` helper:

```ruby
examples = ADEExampleGEPA.build_examples(rows)
train, val, test = ADEExampleGEPA.split_examples(examples, train_ratio: 0.6, val_ratio: 0.2)
baseline = ADEExampleGEPA.evaluate(program, test)
```

Any GEPA run should keep a held-out test set so you can confirm improvements outside the optimization loop.

### 3. Design a metric that returns `DSPy::Prediction`

GEPA expects richer feedback than a plain boolean. Borrow the ADE pattern:

```ruby
metric = lambda do |example, prediction|
  expected = example.expected_values[:label]
  predicted = ADEExampleGEPA.label_from_prediction(prediction)

  score = predicted == expected ? 1.0 : 0.0
  feedback = if score == 1.0
    "Correct classification for #{expected.serialize}"
  else
    "Misclassified: expected #{expected.serialize}, predicted #{predicted.serialize}"
  end

  DSPy::Prediction.new(score: score, feedback: feedback)
end
```

Return scores in `[0, 1]` and include human-readable feedback. GEPA logs both in telemetry and feeds the text to the reflection LM.

### 4. (Optional) Add predictor-level feedback hooks

`feedback_map` lets you target individual predictors inside a composite module. The ADE demo runs GEPA over a simple predictor, so the map keys just use `'self'`:

```ruby
feedback_map = {
  'self' => lambda do |predictor_output:, predictor_inputs:, module_inputs:, module_outputs:, captured_trace:|
    expected = module_inputs.expected_values[:label]
    predicted = ADEExampleGEPA.label_from_prediction(predictor_output)

    DSPy::Prediction.new(
      score: predicted == expected ? 1.0 : 0.0,
      feedback: "Classifier saw '#{predictor_inputs[:text][0..60]}...' => #{predicted.serialize}"
    )
  end
}
```

Leave `feedback_map` empty if your metric already describes everything. For multi-predictor chains, add entries per component so the reflection LM can see localized feedback.

### 5. Configure the teleprompter

```ruby
teleprompter = DSPy::Teleprompt::GEPA.new(
  metric: metric,
  reflection_lm: DSPy::ReflectionLM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']),
  feedback_map: feedback_map,
  config: {
    max_metric_calls: 600,
    minibatch_size: 6,
    skip_perfect_score: false
  }
)
```

Key knobs:

- `max_metric_calls`: Hard budget on how many evaluation calls GEPA can spend. Set it to at least the validation set size plus a few minibatches.
- `minibatch_size`: Number of examples per reflective replay batch. Lower values give faster iterations; higher values stabilize scores.
- `skip_perfect_score`: Set to `true` if you want GEPA to bail out when it finds a candidate with score `1.0`.

### 6. Compile and evaluate

```ruby
result = teleprompter.compile(program, trainset: train, valset: val)
optimized_program = result.optimized_program

test_metrics = ADEExampleGEPA.evaluate(optimized_program, test)
```

The returned `result` exposes:

- `optimized_program`: ready-to-use `DSPy::Predict` with updated instruction and few-shot examples.
- `best_score_value`: validation score for the best candidate.
- `metadata`: map containing candidate counts, trace hashes, and telemetry IDs.

## Reading the Outputs

The ADE example writes two artifacts to `examples/ade_optimizer_gepa/results/`:

- `gepa_summary.json`: timestamp, config, baseline vs optimized metrics.
- `gepa_metrics.csv`: quick comparison table for accuracy, precision, recall, and F1.

You can adopt the same pattern or plug `GEPA::Logging::ExperimentTracker` into your own persistence layer:

```ruby
tracker = GEPA::Logging::ExperimentTracker.new
tracker.with_subscriber { |event| MyModel.create!(payload: event) }
```

Add the tracker to `DSPy::Teleprompt::GEPA.new` via `experiment_tracker: tracker`.

## Advanced Configuration

- **Reflection LM substitutions**: swap `DSPy::ReflectionLM` for any callable object that accepts the reflection prompt hash and returns a string. Ensure the model echoes the new instruction inside triple backticks; the default reflection signature handles extraction.
- **Custom acceptance**: pass `acceptance_strategy:` to plug in bespoke Pareto filters or early-stop heuristics.
- **Telemetry**: spans emit automatically via `GEPA::Telemetry`. Enable global observability with `DSPy.configure { |c| c.observability = true }` to stream spans to your OpenTelemetry exporter.
- **Merge proposer**: use `config[:enable_merge_proposer] = true` to recombine top candidates when you want broader exploration after convergence.

## Troubleshooting

- **Bundler errors**: run `bundle install` from the repository root before executing the example script.
- **Metric budget exhausted**: increase `--max-metric-calls` or shrink `--minibatch-size`. GEPA needs enough budget to evaluate the validation set each iteration.
- **Reflection LM failures**: verify `OPENAI_API_KEY` is set and that your LM supports plain-text completions. GEPA disables structured outputs for compatibility.
- **No improvement**: try seeding GEPA with richer training data, lower the minibatch size, or provide more specific feedback strings so the reflection LM can reason about mistakes.

## Next Steps

Use the ADE workflow as a template:

1. Swap in your own signature and dataset builder.
2. Customize the metric and optional feedback map.
3. Tune `max_metric_calls` and `minibatch_size` for your task.
4. Persist GEPA telemetry/metrics using the experiment tracker.

With a few dozen lines of glue, GEPA becomes a drop-in evolutionary loop that keeps your Ruby prompts improving over time.
