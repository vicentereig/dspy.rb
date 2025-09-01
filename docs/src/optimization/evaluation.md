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
# Create an evaluator with a metric
evaluator = DSPy::Evaluate.new(metric: :exact_match)

# Evaluate a predictor
result = evaluator.evaluate(
  examples: test_examples,
  display_table: true
) do |example|
  # Your prediction logic
  predictor.call(input: example.input)
end

puts "Score: #{result.score}"
puts "Passed: #{result.passed_count}/#{result.total_count}"
```

### Using Different Metrics

```ruby
# Exact match - outputs must match exactly
evaluator = DSPy::Evaluate.new(metric: :exact_match)

# Contains - output must contain expected value
evaluator = DSPy::Evaluate.new(metric: :contains)

# Numeric difference - for numeric outputs
evaluator = DSPy::Evaluate.new(metric: :numeric_difference)

# Composite AND - all conditions must pass
evaluator = DSPy::Evaluate.new(metric: :composite_and)
```

## Custom Metrics

### Defining Custom Metrics

```ruby
# Custom metric as a proc
accuracy_metric = ->(example, prediction) do
  return false unless prediction && prediction.label
  prediction.label.downcase == example.expected_label.downcase
end

evaluator = DSPy::Evaluate.new(metric: accuracy_metric)
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

evaluator = DSPy::Evaluate.new(metric: quality_metric)
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
evaluator = DSPy::Evaluate.new(
  metric: :exact_match,
  num_threads: 4  # Process 4 examples concurrently
)

# Note: Currently num_threads is accepted but not used in evaluation
# All examples are processed sequentially
```

## Integration with Optimizers

### Evaluation in Optimization

```ruby
# Define evaluation for optimization
def evaluate_candidate(predictor, dev_examples)
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  
  result = evaluator.evaluate(examples: dev_examples) do |example|
    predictor.call(question: example.question)
  end
  
  result.score
end

# Use in optimizer
optimizer = DSPy::MIPROv2.new(
  signature: QASignature,
  mode: :medium
)

result = optimizer.optimize(
  examples: train_examples,
  val_examples: dev_examples
) do |predictor, examples|
  evaluate_candidate(predictor, examples)
end
```

## Best Practices

### 1. Choose Appropriate Metrics

```ruby
# For classification
evaluator = DSPy::Evaluate.new(metric: :exact_match)

# For text generation with flexibility
evaluator = DSPy::Evaluate.new(metric: :contains)

# For custom domain logic
evaluator = DSPy::Evaluate.new(metric: domain_specific_metric)
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
