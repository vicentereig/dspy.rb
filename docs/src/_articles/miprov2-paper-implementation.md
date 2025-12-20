---
layout: blog
title: "MIPROv2 Paper: How Stanford's Prompt Optimization Works in Ruby"
date: 2025-12-20
description: "Deep dive into the MIPROv2 paper (arXiv:2406.11695) from Stanford. Learn how Bayesian optimization, dataset summarization, and instruction bootstrapping combine to improve LLM prompts automatically. Ruby implementation included."
author: "Vicente Reig"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/miprov2-paper-implementation/"
image: /images/og/miprov2-paper-implementation.png
reading_time: "8 min read"
---

Stanford's MIPROv2 paper[^miprov2-paper] introduces a systematic approach to prompt optimization that eliminates guesswork. Instead of manually tweaking prompts, you define a metric and let the optimizer find instructions that actually improve your scores. This article breaks down the key ideas from the paper and shows how DSPy.rb implements them.

## The Problem MIPROv2 Solves

Traditional prompt engineering is trial-and-error. You write a prompt, test it on a few examples, adjust wording, and repeat. This approach has three fundamental issues:

1. **No systematic exploration**: You only test the prompts you think of
2. **Evaluation blind spots**: Manual testing rarely covers edge cases
3. **Multi-stage complexity**: When your program has multiple LLM calls, improvements to one stage can hurt another

MIPROv2 treats prompt optimization as a search problem. Given a program with typed signatures, a dataset, and a metric, it systematically proposes and evaluates instruction candidates until it finds one that maximizes your objective.

## Key Ideas from the Paper

### 1. Dataset Summarization

Before generating instruction candidates, MIPROv2 analyzes your training examples to understand the task:

```ruby
# DSPy.rb's DatasetSummaryGenerator creates context for instruction proposals
summary = DSPy::Teleprompt::DatasetSummaryGenerator.new.generate(
  trainset: examples,
  signature: ADETextClassifier
)
# => "This dataset contains clinical sentences labeled for adverse drug events..."
```

This summary grounds instruction proposals in your actual data, preventing the optimizer from suggesting prompts that don't match your domain.

### 2. Instruction Bootstrapping

The optimizer generates multiple instruction candidates per trial, then selects the best:

```ruby
DSPy::Teleprompt::MIPROv2.new(metric: metric).tap do |opt|
  opt.configure do |config|
    config.num_instruction_candidates = 3  # Candidates per trial
    config.bootstrap_sets = 2               # Few-shot demo batches
  end
end
```

The paper found that generating 3-5 candidates per trial balances exploration with compute cost. More candidates increase the chance of finding a good prompt, but each requires evaluation.

### 3. Bayesian Optimization

MIPROv2 uses Gaussian Process surrogate models to guide the search. Instead of random exploration, it:

1. Maintains a model of which instruction features lead to higher scores
2. Proposes candidates that balance exploitation (similar to past winners) with exploration (novel regions)
3. Updates the model after each trial based on observed performance

This adaptive search is why MIPROv2 often finds better prompts in fewer trials than random search.

### 4. Mini-batch Evaluation

Evaluating every candidate on your full validation set is expensive. The paper introduces stochastic evaluation:

```ruby
config.minibatch_size = 10  # Evaluate on 10 examples per trial
```

Mini-batches provide noisy but cheap fitness signals. The Bayesian optimizer handles the noise, extracting signal from multiple trials. This lets you run more trials within the same API budget.

### 5. Per-Predictor Optimization

For multi-stage programs (like ReAct agents), MIPROv2 optimizes each predictor independently while measuring end-to-end performance:

```ruby
# A ReAct agent has multiple predictors
react_agent = DSPy::ReAct.new(TaskSignature, tools: toolset)

# MIPROv2 optimizes thought_generator, observation_processor separately
# but evaluates using your end-to-end metric
result = optimizer.compile(react_agent, trainset: train, valset: val)
```

The optimizer credits improvements to specific predictors, so you can see which stage needed better instructions.

## DSPy.rb Implementation

The Ruby port faithfully implements the paper's algorithms while adapting to Ruby idioms. Here's how to use it:

### Installation

MIPROv2 ships as a separate gem to keep the Gaussian Process dependencies optional:

```ruby
# Gemfile
gem "dspy"
gem "dspy-miprov2"
```

### Basic Usage

```ruby
require "dspy"
require "dspy/miprov2"

# Define your task with a typed signature
class SentimentClassifier < DSPy::Signature
  description "Classify the sentiment of customer feedback"

  input do
    const :text, String
  end

  output do
    const :sentiment, SentimentLabel  # Positive, Negative, Neutral
    const :confidence, Float
  end
end

# Create baseline program
program = DSPy::Predict.new(SentimentClassifier)

# Define your success metric
metric = proc do |example, prediction|
  prediction.sentiment == example.expected_values[:sentiment]
end

# Configure MIPROv2 with a preset
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
optimizer.configure { |c| c.auto_preset = :medium }  # 12 trials

# Run optimization
result = optimizer.compile(program, trainset: train, valset: val)

# Use the optimized program
optimized = result.optimized_program
```

### Preset Reference

The presets follow the paper's guidance on trial budgets:

| Preset | Trials | Instruction Candidates | Use Case |
|--------|--------|------------------------|----------|
| `light` | 6 | 3 | Quick prototyping, small datasets |
| `medium` | 12 | 4 | Production pilots, balanced exploration |
| `heavy` | 18 | 5 | Maximum accuracy, multi-stage programs |

### Inspecting Results

MIPROv2 provides detailed optimization traces:

```ruby
# Best score achieved
puts result.best_score_value  # => 0.87

# Trial-by-trial logs
result.optimization_trace[:trial_logs].each do |trial|
  puts "Trial #{trial[:trial_num]}: #{trial[:score]}"
  puts "  Instruction: #{trial[:instruction]}"
end

# Predictor-level insights (for multi-stage programs)
result.metadata[:predictor_contributions].each do |predictor, improvement|
  puts "#{predictor}: +#{improvement} points"
end
```

## Results from the Paper

The Stanford team evaluated MIPROv2 on several benchmarks:

- **Multi-hop QA**: Up to 13% accuracy improvement over baseline prompts
- **Mathematical reasoning**: 8% improvement on GSM8K
- **Instruction following**: Significant gains on multi-stage programs

The key finding: automatic optimization consistently outperforms expert-written prompts, especially on complex tasks where human intuition fails.

## When to Use MIPROv2

MIPROv2 shines when:

1. **You have labeled examples**: The optimizer needs training data to evaluate candidates
2. **Your metric is measurable**: Accuracy, F1, pass rate, or any numeric score
3. **Manual tuning has plateaued**: Human intuition only takes you so far
4. **Multi-stage programs**: Per-predictor optimization handles complex pipelines

For simple single-call tasks, start with [GEPA](https://oss.vicente.services/dspy.rb/optimization/gepa/) for faster iteration. Use MIPROv2 when you need the highest accuracy or have multiple predictors.

## Further Reading

- [MIPROv2 Documentation](https://oss.vicente.services/dspy.rb/optimization/miprov2/) - Complete usage guide
- [GEPA Optimizer](https://oss.vicente.services/dspy.rb/optimization/gepa/) - Lighter-weight alternative
- [Evaluation Framework](https://oss.vicente.services/dspy.rb/optimization/evaluation/) - Building metrics
- [Getting Started](https://oss.vicente.services/dspy.rb/getting-started/) - New to DSPy.rb?

[^miprov2-paper]: Opsahl-Ong, Krista, et al. *Optimizing Instructions and Demonstrations for Multi-Stage Language Model Programs.* arXiv:2406.11695v2, 2024. [Read the paper](https://arxiv.org/abs/2406.11695)
