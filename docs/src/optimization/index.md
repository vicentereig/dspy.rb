---
layout: docs
title: Optimization
description: Evaluate DSPy.rb programs and compile instructions and examples against a metric
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-07-23 00:00:00 +0000
---
# Optimization

Optimizers search over supported program parameters, including instructions and few-shot examples. You supply examples, a metric, and a budget; the optimizer returns the best candidate it found.

Optimization does not define quality for you. Build and inspect the metric first, preserve a held-out test set, and record the model and dataset used for each run.

## Choose an Evaluation or Optimization Task

### [Evaluation](./evaluation/)
Build metrics and evaluation frameworks to measure and improve your modules systematically.

### [Score Reporting](/dspy.rb/production/score-reporting/)
Attach typed metric results to executions and, when configured, export them to Langfuse.

### [Benchmarking Raw Prompts](./benchmarking-raw-prompts/)
Compare an existing prompt with a DSPy module under the same models, examples, and measurements.

### [Choose an Optimizer](./prompt-optimization/)
Revise instructions and examples immutably, measure a baseline, and choose an optimizer from the measured failure and feedback shape.

### [GEPA](./gepa/)
Use reflective feedback to evolve supported program parameters after establishing an evaluation baseline.

### [MIPROv2](./miprov2/)
Use Bayesian search to select instructions and demonstrations for single- or multi-predictor programs.

## Establish Evidence Before Optimizing

1. Define and test an [evaluation metric](./evaluation/).
2. Compare against a [raw-prompt baseline](./benchmarking-raw-prompts/) when replacing an existing prompt.
3. Read [Choose an Optimizer](./prompt-optimization/), then select [GEPA](./gepa/) or [MIPROv2](./miprov2/) from the evidence each requires.
