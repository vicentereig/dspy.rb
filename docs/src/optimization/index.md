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

## Optimization Guides

### [Program Optimization](./prompt-optimization/)
Revise instructions and examples immutably, measure a baseline, and compile a program against a metric.

### [MIPROv2](./miprov2/)
Use Bayesian search to select instructions and demonstrations for single- or multi-predictor programs.

### [Evaluation](./evaluation/)
Build metrics and evaluation frameworks to measure and improve your modules systematically.

### [Benchmarking Raw Prompts](./benchmarking-raw-prompts/)
Compare an existing prompt with a DSPy module under the same models, examples, and measurements.

## Getting Started

1. Define and test an [evaluation metric](./evaluation/).
2. Read the [program optimization](./prompt-optimization/) guide.
3. Choose [MIPROv2](./miprov2/) or [GEPA](./gepa/) based on the feedback your metric can provide.
