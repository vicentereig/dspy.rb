---
layout: docs
title: "GEPA Optimizer for Ruby — Reflective Prompt Evolution"
name: GEPA Optimizer
description: "Configure GEPA in Ruby with scalar scores, textual feedback, a reflection model, and a bounded evaluation budget."
date: 2025-07-10 00:00:00 +0000
---
# GEPA Optimizer

See the [package and capability matrix](/dspy.rb/getting-started/packages/) for the distinction between the public `dspy-gepa` integration and its lower-level `gepa` dependency.

GEPA stands for **Genetic-Pareto Reflective Prompt Evolution**. In practice, it is a feedback loop: run your DSPy module on a small batch, collect both scores and short text notes about what happened, and let a reflection model rewrite the instruction. If the rewrite helps on the validation set without regressing elsewhere, GEPA keeps it as a new candidate on the Pareto frontier.

The walkthrough uses `examples/ade_optimizer_gepa/` as a concrete implementation. Replace its signature, dataset, and metric while retaining the budget and held-out evaluation structure.

## Installation

Add the optional gem so Bundler pulls in the DSPy.rb optimizer integration and its GEPA core dependency:

```ruby
gem 'dspy'
gem 'dspy-gepa'
```

If you're working inside the DSPy.rb monorepo, set `DSPY_WITH_GEPA=1 bundle install` so the local gemspecs are included. The `dspy-gepa` gem depends on the `gepa` core optimizer gem automatically.

## Understand the GEPA Loop

GEPA runs in iterative loops:

- **Replay traces** collected during minibatch evaluation.
- **Summarize feedback** from your metric and optional predictor-level hooks.
- **Ask the reflection LM** to propose an improved instruction.
- **Accept or reject** the new candidate using Pareto dominance on score and novelty.

DSPy.rb's GEPA implementation includes telemetry, merge proposers, and experiment tracking. Supply a DSPy module and a metric that returns `DSPy::Prediction`; add a `feedback_map` when individual predictors need separate feedback.

## Quickstart (ADE demo)

The ADE demo optimizes a clinical text classifier with GEPA. Run it end-to-end:

```bash
bundle exec ruby examples/ade_optimizer_gepa/main.rb \
  --limit 30 \
  --max-metric-calls 600 \
  --minibatch-size 6
```

- Uses `DSPy::Teleprompt::GEPA` with a reflective OpenAI LM.
- Requires the optional `dspy-gepa` gem (see installation notes above).
- Downloads a small ADE dataset, splits into train/val/test, and logs results under `examples/ade_optimizer_gepa/results/`.
- Raises `max_metric_calls` to the validation-set size when the configured budget is lower.

Reuse this dataset, metric, budget, and held-out-test structure with the application task.

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
  expected  = example.expected_values[:label]
  predicted = ADEExampleGEPA.label_from_prediction(prediction)
  snippet   = ADEExampleGEPA.snippet(example.input_values[:text])

  score = predicted == expected ? 1.0 : 0.0
  feedback = if score == 1.0
    "Correct (#{expected.serialize}) for: \"#{snippet}\""
  else
    "Misclassified (expected #{expected.serialize}, predicted #{predicted.serialize}) for: \"#{snippet}\""
  end

  DSPy::Prediction.new(score: score, feedback: feedback)
end
```

The helper `ADEExampleGEPA.snippet` trims long sentences so the feedback stays readable. Keep the score in `[0, 1]` and always return a short message that explains what happened—GEPA saves both fields and hands the text to the reflection model so it understands the failure.

### 4. (Optional) Add predictor-level feedback hooks

`feedback_map` lets you target individual predictors inside a composite module. The ADE demo runs GEPA over a simple predictor, so the map keys just use `'self'`:

```ruby
feedback_map = {
  'self' => lambda do |predictor_output:, predictor_inputs:, module_inputs:, module_outputs:, captured_trace:|
    expected  = module_inputs.expected_values[:label]
    predicted = ADEExampleGEPA.label_from_prediction(predictor_output)
    snippet   = ADEExampleGEPA.snippet(predictor_inputs[:text], length: 80)

    DSPy::Prediction.new(
      score: predicted == expected ? 1.0 : 0.0,
      feedback: "Classifier saw \"#{snippet}\" → #{predicted.serialize} (expected #{expected.serialize})"
    )
  end
}
```

Leave `feedback_map` empty if your metric already covers the basics. For multi-predictor chains, add entries per component so the reflection LM sees localized context at each step.

### 5. Configure the Optimizer

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

- `max_metric_calls`: Hard budget on how many evaluation calls GEPA can spend. Set it to at least the validation set size plus a few minibatches so GEPA can evaluate more than just the seed candidate.
- `minibatch_size`: Number of examples per reflective replay batch. Smaller values (<6) make each iteration cheaper and let you try more prompt variants. Larger values (10–15) average over more data so scores bounce around less, but you burn through the budget faster.
- `skip_perfect_score`: Set to `true` if you want GEPA to bail out when it finds a candidate with score `1.0`.

#### Minibatch sizing cheat sheet

| You care about… | Suggested `minibatch_size` | Why |
| --- | --- | --- |
| Exploring many candidates within a tight budget | 3–6 | Cheap iterations mean more opportunities for the reflection LM to try new prompts, albeit with noisier metrics. |
| Stable metrics when each rollout is costly | 8–12 | Larger batches smooth out randomness but leave room for fewer candidates unless you also raise `--max-metric-calls`. |
| Investigating specific failure modes | Start at 3–4, then raise to 8+ once patterns emerge | Begin with breadth, and once you identify consistent issues, increase the batch size to confirm fixes under steadier scores. |

### 6. Compile and evaluate

```ruby
result = teleprompter.compile(program, trainset: train, valset: val)
optimized_program = result.optimized_program

test_metrics = ADEExampleGEPA.evaluate(optimized_program, test)
```

The returned `result` exposes:

- `optimized_program`: `DSPy::Predict` with the selected instruction and few-shot examples; evaluate it before promotion.
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

## Guiding Principles from Agrawal et al. (2025)

The GEPA paper by Agrawal et al. (2025)[^gepa-paper] highlights patterns that make reflective prompt evolution efficient:

- **Explore via Pareto fronts**: keep a diverse candidate pool and sample from the Pareto frontier instead of mutating only the top-scoring program. This balances exploration and prevents the search from getting stuck on a single lineage.
- **Prioritize reflective mutations**: run minibatch rollouts, gather traces, and rewrite only the targeted module so every iteration carries concrete lessons from the feedback signal.
- **Upgrade metrics into `µ_f`**: emit both scalar scores and textual diagnostics (including evaluator traces) so the reflection LM can reason about failures rather than only seeing pass/fail flags.
- **Budget around data splits**: dedicate the training split to learning signals, use the validation split strictly for candidate selection, and align the total rollout budget with your constraints so you can compare optimizers fairly.
- **Tune minibatches and validation usage**: smaller minibatches keep iteration cost low; if validation rollouts dominate the budget, shrink or subsample the validation set to maintain headroom for new candidates.
- **Schedule merges deliberately**: only enable module-level merge/crossover after multiple strong lineages emerge; premature merges eat budget without meaningful gains.
- **Reuse GEPA for inference-time search**: when solving a fixed batch of tasks, place the same dataset in both training and validation to iteratively overfit each item while sharing lessons across tasks.

### Applying the principles in `examples/ade_optimizer_gepa/main.rb`

The ADE demo script already follows most of these recommendations. To extend it:

1. **Pareto-friendly budget**: keep `--max-metric-calls` comfortably above the validation set size so GEPA can evaluate multiple candidates before exhausting the budget.
2. **Rich feedback**: expand the metric lambda in `ADEExampleGEPA.metric` to return descriptive failure messages (e.g., include the misclassified span) so reflective mutations see actionable context; the ADE demo now embeds short sentence snippets in both metric and predictor-level feedback.
3. **Validation discipline**: keep the validation split for candidate selection and inspect `results/gepa_summary.json` for results on the held-out test split.
4. **Track candidates**: run with `--track-stats` (or enable the experiment tracker manually) when you want to audit whether GEPA is proposing genuinely new prompts instead of recycling the seed instruction.
5. **Merge gating**: leave merge disabled for the small ADE module, but if you experiment with larger pipelines, gate merge on reaching several validated candidates before flipping `config[:enable_merge_proposer]`.

Copy-paste helpers:

```bash
bundle exec ruby examples/ade_optimizer_gepa/main.rb \
  --limit 200 \
  --seed 123 \
  --minibatch-size 6 \
  --max-metric-calls 900

cat examples/ade_optimizer_gepa/results/gepa_summary.json
column -t -s, examples/ade_optimizer_gepa/results/gepa_metrics.csv

bundle exec ruby examples/ade_optimizer_gepa/main.rb \
  --limit 200 \
  --max-metric-calls 900 \
  --track-stats
head examples/ade_optimizer_gepa/results/gepa_events.jsonl
```

The JSONL log contains every Pareto update and merge decision, so you can inspect candidate evolution with tools like `jq` or `rg`.

## Troubleshooting

- **Bundler errors**: run `bundle install` from the repository root before executing the example script.
- **Metric budget exhausted**: increase `--max-metric-calls` or shrink `--minibatch-size`. GEPA needs enough budget to evaluate the validation set each iteration.
- **Reflection LM failures**: verify `OPENAI_API_KEY` is set and that your LM supports plain-text completions. GEPA disables structured outputs for compatibility.
- **No improvement**: try seeding GEPA with richer training data, lower the minibatch size, or provide more specific feedback strings so the reflection LM can reason about mistakes.

## Adapt the Workflow

Use the ADE workflow as a template:

1. Swap in your own signature and dataset builder.
2. Customize the metric and optional feedback map.
3. Tune `max_metric_calls` and `minibatch_size` for your task.
4. Persist GEPA telemetry/metrics using the experiment tracker.

Promote `result.optimized_program` only after evaluating it on data GEPA did not use for candidate selection.

[^gepa-paper]: Lakshya A. Agrawal et al., “GEPA: Reflective Prompt Evolution Can Outperform Reinforcement Learning,” arXiv:2507.19457 (2025).
