---
layout: docs
name: Evaluation Framework
description: Systematically test and measure your LLM applications
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: Evaluation Framework
  url: "/optimization/evaluation/"
prev:
  name: Optimization
  url: "/optimization/"
next:
  name: Prompt Optimization
  url: "/optimization/prompt-optimization/"
date: 2025-07-10 00:00:00 +0000
---
# Evaluation Framework

DSPy.rb provides a comprehensive evaluation framework for systematically testing and measuring the performance of your LLM applications. It supports both simple and complex evaluation scenarios with built-in and custom metrics.

## Overview

The evaluation framework enables:
- **Systematic Testing**: Evaluate predictors against test datasets
- **Built-in Metrics**: Common metrics like exact match and containment
- **Custom Metrics**: Define domain-specific evaluation logic
- **Batch Processing**: Evaluate multiple examples efficiently
- **Result Analysis**: Detailed results with per-example scores

## Basic Usage

### Simple Evaluation

```ruby
# Create an evaluator with a custom metric
metric = proc do |example, prediction|
  # Return true if prediction matches expected output
  prediction.answer == example.expected_values[:answer]
end

evaluator = DSPy::Evals.new(predictor, metric: metric)

# Evaluate on test examples
result = evaluator.evaluate(
  test_examples,
  display_table: true,
  display_progress: true
)

puts "Pass Rate: #{(result.pass_rate * 100).round(1)}%"
puts "Passed: #{result.passed_examples}/#{result.total_examples}"
```

### Automatic Score Export

Export evaluation scores to Langfuse automatically:

```ruby
# Enable score export for Langfuse integration
evaluator = DSPy::Evals.new(
  predictor,
  metric: metric,
  export_scores: true,        # Export scores for each example
  score_name: 'qa_accuracy'   # Custom score name (default: 'evaluation')
)

result = evaluator.evaluate(test_examples)
# Creates individual scores for each example
# Creates a batch score with overall pass rate at the end
```

The `export_scores` option:
- Emits `score.create` events for each evaluated example
- Creates a batch score with the overall pass rate when evaluation completes
- Scores automatically attach to the current trace context
- Works with the `DSPy::Scores::Exporter` for async Langfuse export

### Built-in Metrics

DSPy.rb provides common metrics in the `DSPy::Metrics` module:

```ruby
# Exact match - prediction must exactly match expected value
metric = DSPy::Metrics.exact_match(
  field: :answer,           # Field to compare (default: :answer)
  case_sensitive: true      # Case-sensitive comparison (default: true)
)
evaluator = DSPy::Evals.new(predictor, metric: metric)

# Contains - prediction must contain expected substring
metric = DSPy::Metrics.contains(
  field: :answer,           # Field to compare (default: :answer)
  case_sensitive: false     # Case-insensitive by default
)
evaluator = DSPy::Evals.new(predictor, metric: metric)

# Numeric difference - for numeric outputs within tolerance
metric = DSPy::Metrics.numeric_difference(
  field: :answer,           # Field to compare (default: :answer)
  tolerance: 0.01           # Acceptable difference (default: 0.01)
)
evaluator = DSPy::Evals.new(predictor, metric: metric)

# Composite AND - all metrics must pass
metric1 = DSPy::Metrics.exact_match(field: :answer)
metric2 = DSPy::Metrics.contains(field: :reasoning)
metric = DSPy::Metrics.composite_and(metric1, metric2)
evaluator = DSPy::Evals.new(predictor, metric: metric)
```

## Observability Hooks

`DSPy::Evals` exposes callback hooks so you can plug in logging, telemetry, or Langfuse reporting without editing the evaluator. Callbacks receive a payload describing the current run, and they fire exactly where you register them.

```ruby
# Log each example before it is scored
DSPy::Evals.before_example do |payload|
  example = payload[:example]
  DSPy.logger.info("Evaluating example #{example.id}") if example.respond_to?(:id)
end

# Send aggregate metrics to Langfuse when a batch completes
DSPy::Evals.after_batch do |payload|
  result = payload[:result]
  Langfuse.event(
    name: 'eval.batch',
    metadata: {
      total: result.total_examples,
      passed: result.passed_examples,
      score: result.score
    }
  )
end
```

Callbacks mirror the Python API: use `before_example` / `after_example` for single predictions and `before_batch` / `after_batch` for full evaluations. Because the evaluator manages callback execution, you can interleave telemetry with custom spans or multithreaded runs without wrapping the methods yourself.

## Custom Metrics

### Defining Custom Metrics

```ruby
# Custom metric as a proc
accuracy_metric = ->(example, prediction) do
  return false unless prediction && prediction.label
  prediction.label.downcase == example.expected_label.downcase
end

evaluator = DSPy::Evals.new(metric: accuracy_metric)
```

### Complex Custom Metrics

```ruby
# Multi-factor evaluation
quality_metric = ->(example, prediction) do
  return false unless prediction
  
  score = 0.0
  
  # Check accuracy
  if prediction.answer == example.expected_answer
    score += 0.5
  end
  
  # Check completeness
  if prediction.explanation && prediction.explanation.length > 50
    score += 0.3
  end
  
  # Check confidence
  if prediction.confidence && prediction.confidence > 0.8
    score += 0.2
  end
  
  score >= 0.7  # Pass threshold
end

evaluator = DSPy::Evals.new(metric: quality_metric)
```

## Evaluation Results

### Working with Results

```ruby
result = evaluator.evaluate(examples: test_examples) do |example|
  predictor.call(text: example.text)
end

# Access overall metrics
puts "Score: #{result.score}"
puts "Passed: #{result.passed_count}"
puts "Failed: #{result.failed_count}"
puts "Total: #{result.total_count}"

# Access individual results
result.results.each do |individual_result|
  puts "Example: #{individual_result.example.text}"
  puts "Passed: #{individual_result.passed}"
  puts "Score: #{individual_result.score}"
  
  if individual_result.error
    puts "Error: #{individual_result.error}"
  end
end
```

### Batch Results

When evaluation completes, you get a `BatchEvaluationResult` with:
- `score`: Overall score (0.0 to 1.0)
- `passed_count`: Number of examples that passed
- `failed_count`: Number of examples that failed  
- `error_count`: Number of examples that errored
- `results`: Array of individual `EvaluationResult` objects

## Display Options

### Table Display

```ruby
# Show results in a formatted table
result = evaluator.evaluate(
  examples: test_examples,
  display_table: true,
  display_progress: true
) do |example|
  predictor.call(input: example.input)
end
```

This displays:
- Progress updates during evaluation
- Final summary table with pass/fail counts
- Overall score

### Custom Display

```ruby
# Suppress default display
result = evaluator.evaluate(
  examples: test_examples,
  display_table: false,
  display_progress: false
) do |example|
  predictor.call(input: example.input)
end

# Custom result formatting
puts "=" * 50
puts "Evaluation Complete"
puts "=" * 50
puts "Accuracy: #{(result.score * 100).round(1)}%"
puts "Details:"
result.results.each_with_index do |r, i|
  status = r.passed ? "✓" : "✗"
  puts "  #{i+1}. #{status} #{r.example.text[0..30]}..."
end
```

## Error Handling

### Graceful Error Handling

```ruby
result = evaluator.evaluate(examples: test_examples) do |example|
  begin
    predictor.call(input: example.input)
  rescue => e
    # Errors are captured in results
    nil
  end
end

# Check for errors
errors = result.results.select { |r| r.error }
if errors.any?
  puts "#{errors.count} examples failed with errors:"
  errors.each do |r|
    puts "  - #{r.example.id}: #{r.error}"
  end
end
```

## Multi-Threading

The evaluator supports concurrent evaluation:

```ruby
# Initialize with thread count
evaluator = DSPy::Evals.new(
  metric: :exact_match,
  num_threads: 4  # Process 4 examples concurrently
)

# Note: Currently num_threads is accepted but not used in evaluation
# All examples are processed sequentially
```

## Integration with Optimizers

### Evaluation in Optimization

```ruby
# Define evaluation metric for optimization
metric = proc do |example, prediction|
  # Custom evaluation logic
  expected = example.expected_values[:answer].to_s.strip.downcase
  predicted = prediction.respond_to?(:answer) ? prediction.answer.to_s.strip.downcase : ''
  !expected.empty? && predicted.include?(expected)
end

# Create optimizer with metric
program = DSPy::Predict.new(QASignature)
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium(metric: metric)

result = optimizer.compile(
  program,
  trainset: train_examples,
  valset: dev_examples
)

# Evaluate optimized program on test set
evaluator = DSPy::Evals.new(result.optimized_program, metric: metric)
test_result = evaluator.evaluate(test_examples, display_table: true)

puts "Test accuracy: #{(test_result.pass_rate * 100).round(2)}%"
```

## Best Practices

### 1. Choose Appropriate Metrics

```ruby
# For classification tasks
metric = DSPy::Metrics.exact_match(field: :label, case_sensitive: true)
evaluator = DSPy::Evals.new(predictor, metric: metric)

# For text generation with flexibility
metric = DSPy::Metrics.contains(field: :answer, case_sensitive: false)
evaluator = DSPy::Evals.new(predictor, metric: metric)

# For custom domain logic
metric = proc do |example, prediction|
  # Your domain-specific validation logic
  prediction.meets_requirements?(example.requirements)
end
evaluator = DSPy::Evals.new(predictor, metric: metric)
```

### 2. Handle Edge Cases

```ruby
robust_metric = ->(example, prediction) do
  # Handle nil predictions
  return false unless prediction
  
  # Handle missing fields
  return false unless prediction.respond_to?(:answer)
  
  # Normalize before comparison
  predicted = prediction.answer.to_s.strip.downcase
  expected = example.expected.to_s.strip.downcase
  
  predicted == expected
end
```

### 3. Meaningful Error Messages

```ruby
result = evaluator.evaluate(examples: examples) do |example|
  prediction = predictor.call(input: example.input)
  
  # Add context for debugging
  if prediction.nil?
    raise "Predictor returned nil for example: #{example.id}"
  end
  
  prediction
end
```

### 4. Batch Size Considerations

For large datasets, process in batches:

```ruby
all_examples = load_large_dataset()
batch_size = 100
results = []

all_examples.each_slice(batch_size) do |batch|
  result = evaluator.evaluate(examples: batch) do |example|
    predictor.call(input: example.input)
  end
  results << result
end

# Aggregate results
total_passed = results.sum(&:passed_count)
total_count = results.sum(&:total_count)
overall_score = total_passed.to_f / total_count
```
