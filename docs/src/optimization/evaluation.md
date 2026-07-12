---
layout: docs
name: Evaluation Framework
description: Evaluate DSPy.rb programs against typed examples and explicit metrics
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: Evaluation Framework
  url: "/optimization/evaluation/"
prev:
  name: Optimization
  url: "/optimization/"
next:
  name: Program Optimization
  url: "/optimization/prompt-optimization/"
date: 2025-07-10 00:00:00 +0000
---
# Evaluation Framework

`DSPy::Evals` runs a program against `DSPy::Example` objects and applies a metric to each prediction. Evaluation measures the behavior named by that metric; typed output validation alone does not establish correctness.

## Define Examples

Examples use the same signature as the program:

```ruby
class Sentiment < DSPy::Signature
  input do
    const :text, String
  end

  output do
    const :label, String
  end
end

examples = [
  DSPy::Example.new(
    signature_class: Sentiment,
    input: { text: "The release fixed my issue." },
    expected: { label: "positive" },
    id: "positive-1"
  ),
  DSPy::Example.new(
    signature_class: Sentiment,
    input: { text: "The request timed out." },
    expected: { label: "negative" },
    id: "negative-1"
  )
]
```

Construction validates the input and expected output against the signature. Use `example.input_values` and `example.expected_values` inside metrics and debugging code.

## Define a Metric

A metric receives an example and the program's prediction:

```ruby
exact_label = lambda do |example, prediction|
  prediction.label == example.expected_values[:label]
end
```

Boolean metrics count passing examples. Numeric metrics contribute to the aggregate score. Keep numeric ranges and thresholds explicit so readers can interpret the result.

## Run an Evaluation

Pass the program and metric to `DSPy::Evals`, then evaluate the dataset:

```ruby
program = DSPy::Predict.new(Sentiment)
evaluator = DSPy::Evals.new(program, metric: exact_label)

result = evaluator.evaluate(
  examples,
  display_progress: true,
  display_table: false
)

puts "Passed: #{result.passed_examples}/#{result.total_examples}"
puts "Pass rate: #{result.pass_rate}"
puts "Score: #{result.score}"
```

`BatchEvaluationResult#score` is expressed on a 0-100 scale. `pass_rate` is expressed on a 0-1 scale.

## Inspect Failures

Each `EvaluationResult` contains the example, prediction, trace, metric values, and pass status:

```ruby
result.results.reject(&:passed).each do |failure|
  puts "Example: #{failure.example.id}"
  puts "Input: #{failure.example.input_values.inspect}"
  puts "Expected: #{failure.example.expected_values.inspect}"
  puts "Prediction: #{failure.prediction.inspect}"
  puts "Metrics: #{failure.metrics.inspect}"
end
```

Provider or program exceptions are recorded as failed results by the evaluator. Inspect the associated trace and logs for the original exception.

## Use Numeric Scores

A metric can reward partial behavior:

```ruby
quality = lambda do |example, prediction|
  expected = example.expected_values

  score = 0.0
  score += 0.7 if prediction.answer == expected[:answer]
  score += 0.3 if prediction.explanation.to_s.length >= 40
  score
end
```

Do not combine unrelated concerns into one number without recording the components. A single score can hide a regression in the behavior that matters most.

## Run in Parallel

Set `num_threads` on the evaluator when calls are independent:

```ruby
evaluator = DSPy::Evals.new(
  program,
  metric: exact_label,
  num_threads: 4
)

result = evaluator.evaluate(examples)
```

Parallel evaluation increases concurrent provider calls. Keep provider rate limits and the cost of the full dataset in view.

## Evaluate an Optimized Program

Use the same held-out examples and metric for the baseline and optimized program:

```ruby
baseline = DSPy::Evals.new(program, metric: exact_label).evaluate(test_examples)
optimized = DSPy::Evals.new(
  optimization_result.optimized_program,
  metric: exact_label
).evaluate(test_examples)

puts "Baseline: #{baseline.score}"
puts "Optimized: #{optimized.score}"
```

Do not use the optimizer's validation set for this final comparison. Candidate selection has already adapted to that data.

## Metric Design

- Begin with deterministic checks for fields, formats, and known answers.
- Use an LM judge only for behavior that deterministic code cannot express.
- Calibrate judge prompts and thresholds against human-reviewed examples.
- Record separate metrics for correctness, safety, cost, and latency when they lead to different decisions.
- Include failures and boundary cases, not only representative happy paths.
- Version the examples and metric with the program artifact they selected.
