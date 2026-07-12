---
layout: blog
title: "MIPROv2 Paper: How Stanford's Prompt Optimization Works in Ruby"
date: 2025-12-20
description: "How MIPROv2 compiles instructions and demonstrations from examples, metrics, and measured program behavior in DSPy.rb."
author: "Vicente Reig"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/miprov2-paper-implementation/"
image: /images/og/miprov2-paper-implementation.png
reading_time: "8 min read"
---

MIPROv2 starts after you have defined a program and the behavior you will accept. Given training examples, a validation set, and a metric, it searches over instructions and few-shot demonstrations supported by the program. The result is an optimized program artifact, not a prompt someone edited by hand.

Stanford's MIPROv2 paper[^miprov2-paper] describes the method for multi-stage language-model programs. DSPy.rb implements the same broad phases with a Ruby optimizer and a different Bayesian search backend.

## What MIPROv2 Compiles

A DSPy program may contain one predictor or several. Each predictor has parameters such as its instruction and demonstrations. MIPROv2 proposes candidate values for those parameters, runs the complete program, and scores the final behavior with your metric.

That separation matters in a multi-stage program. A locally plausible instruction can make the final result worse. MIPROv2 evaluates candidates through the program's end-to-end objective rather than treating prompt wording as its own goal.

You still choose the objective. Weak examples and a metric that rewards the wrong behavior will produce a well-optimized mistake.

## The Search In Five Phases

### Summarize The Dataset

DSPy.rb's grounded proposer can summarize the training examples and program structure before proposing instructions. The current API performs this inside MIPROv2; `DatasetSummaryGenerator` remains an internal collaborator rather than a public `DSPy::Teleprompt` object.

The summary gives the proposal model evidence about the task. It cannot guarantee that every proposal fits the domain, so candidates still have to survive evaluation.

### Bootstrap Demonstrations

MIPROv2 builds candidate few-shot sets from labeled and bootstrapped examples. These settings control the size of that search surface:

```ruby
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
optimizer.configure do |config|
  config.num_instruction_candidates = 3
  config.bootstrap_sets = 2
  config.max_bootstrapped_examples = 2
  config.max_labeled_examples = 4
end
```

More candidates and demonstration sets increase cost. They widen the search; they do not guarantee a better result.

### Propose Instructions

The grounded proposer uses the signature, program structure, dataset summary, examples, and previous trial information to generate instruction candidates. Developers still write task and field descriptions. MIPROv2 compiles those descriptions and the available evidence into candidate provider-facing instructions.

### Search Candidate Combinations

The paper's reference implementation uses Optuna's TPE sampler. DSPy.rb's `:bayesian` strategy encodes candidate combinations, fits a Gaussian Process, and selects candidates with an Upper Confidence Bound acquisition function. The `:greedy` and `:adaptive` strategies are also available.

The backends differ, and neither is universally better. Their behavior and cost depend on the candidate space and evaluation noise.

```ruby
optimizer.configure do |config|
  config.optimization_strategy = :bayesian
  config.num_trials = 12
  config.minibatch_size = 10
end
```

When `num_threads` is greater than `1`, `minibatch_size` sets the chunk size for parallel candidate evaluation. DSPy.rb evaluates every chunk and combines the results, so each candidate still sees the complete evaluation set. The setting changes scheduling while preserving the evidence and model calls used for an observation.

### Evaluate The Complete Program

For programs that expose multiple predictors, MIPROv2 can apply separate instruction and demonstration candidates to each predictor. The metric still sees the program's final prediction.

This also applies to a `ReAct` module that exposes several predictors. MIPROv2 can optimize supported predictor parameters; it leaves the program's control flow and tool policy unchanged.

## Install The Optional Gem

MIPROv2 ships separately so applications that do not use its numerical dependencies do not have to install them.

```ruby
# Gemfile
gem "dspy"
gem "dspy-miprov2"
```

```ruby
require "dspy"
require "dspy/miprov2"
```

## Compile A Classifier

The signature declares the task. The metric defines acceptable behavior.

```ruby
class SentimentClassifier < DSPy::Signature
  description "Classify the sentiment of customer feedback"

  input do
    const :text, String
  end

  output do
    const :sentiment, SentimentLabel
    const :confidence, Float
  end
end

program = DSPy::Predict.new(SentimentClassifier)

metric = lambda do |example, prediction|
  prediction.sentiment == example.expected_values[:sentiment]
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
optimizer.configure do |config|
  config.auto_preset = DSPy::Teleprompt::AutoPreset::Medium
end

result = optimizer.compile(
  program,
  trainset: train,
  valset: validation
)

optimized_program = result.optimized_program
puts "Best validation score: #{result.best_score_value}"
```

Keep a test set outside the compile loop. The validation score selected the candidate. Estimating generalization requires independent data.

## Presets Are Budgets, Not Quality Levels

Current DSPy.rb presets allocate candidate budgets and configure instruction candidates, bootstrap sets, example limits, search strategy, and early stopping.

| Preset | Candidate budget | Instruction candidates | Search strategy |
|---|---:|---:|---|
| `light` | 6 | 3 | greedy |
| `medium` | 12 | 5 | adaptive |
| `heavy` | 18 | 8 | Bayesian |

For programs with multiple predictors, DSPy.rb derives the number of trials from the candidate budget and number of tunable variables. The budget is therefore more stable to document than a fixed trial count for every program.

Use the smallest preset that can answer the current question. A larger budget spends more model calls and explores more combinations. Production readiness depends on the held-out result and the application's release criteria.

## Inspect What Changed

`MIPROv2Result` exposes the optimized program, best score, evaluated candidates, and optimization trace.

```ruby
puts result.best_score_value

result.optimization_trace[:trial_logs].each do |trial_id, trial|
  puts "Trial #{trial_id}: #{trial[:score]}"
  puts trial[:instruction]
end
```

The exact keys inside each serialized trial depend on the candidate and program shape. Inspect the trace your run produced before building reporting code around nested fields. DSPy.rb does not currently publish a `metadata[:predictor_contributions]` score that attributes improvement to individual predictors.

Evaluate `optimized_program` on the held-out test set and compare it with the baseline under the same metric. Persist the optimized program and enough run metadata to reproduce the decision: dataset version, model configuration, metric version, random seed, and budget.

## What The Paper Establishes

The paper evaluates MIPROv2 across several language-model programs and tasks, comparing optimized programs with baselines under defined metrics.[^miprov2-paper] Those experiments motivate instruction and demonstration search. They do not promise a fixed improvement for a new Ruby application.

Your result depends on the task, model, examples, metric, candidate budget, and variance in model calls. Report the baseline, held-out score, cost, and run configuration rather than carrying a benchmark percentage into another domain.

## When To Use It

MIPROv2 is a reasonable fit when:

- You have enough representative examples to separate training, validation, and test data.
- The metric reflects behavior you are willing to optimize.
- The program has instructions or demonstrations worth compiling.
- The expected gain can justify repeated model calls.

For a small single-predictor program, [GEPA](https://oss.vicente.services/dspy.rb/optimization/gepa/) may provide a more direct reflective optimization loop. Choose between optimizers by their supported parameters, evidence requirements, and budget, then verify the compiled program on held-out data.

## Further Reading

- [MIPROv2 Documentation](https://oss.vicente.services/dspy.rb/optimization/miprov2/)
- [GEPA Optimizer](https://oss.vicente.services/dspy.rb/optimization/gepa/)
- [Evaluation Framework](https://oss.vicente.services/dspy.rb/optimization/evaluation/)
- [Getting Started](https://oss.vicente.services/dspy.rb/getting-started/)

[^miprov2-paper]: Opsahl-Ong, Krista, et al. *Optimizing Instructions and Demonstrations for Multi-Stage Language Model Programs.* arXiv:2406.11695v2, 2024. [Read the paper](https://arxiv.org/abs/2406.11695)
