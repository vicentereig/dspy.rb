# Evaluation Framework

Building reliable LLM applications means systematic testing. DSPy.rb includes a comprehensive evaluation system that works seamlessly with your typed examples and supports multiple evaluation metrics.

## Basic Evaluation

```ruby
# Create your predictor
class MathWord < DSPy::Signature
  description "Solve word problems step by step"
  
  input do
    const :problem, String
  end
  
  output do
    const :answer, Integer
    const :explanation, String
  end
end

math_solver = DSPy::ChainOfThought.new(MathWord)

# Create training examples
training_examples = [
  DSPy::Example.new(
    signature_class: MathWord,
    input: { problem: "Sarah has 5 apples and buys 3 more. How many does she have?" },
    expected: { answer: 8, explanation: "5 + 3 = 8 apples total" }
  ),
  # ... more examples
]

# Evaluate it on your examples
evaluator = DSPy::Evaluate.new(
  math_solver,
  metric: DSPy::Metrics.exact_match  # Built-in exact matching
)

results = evaluator.evaluate(training_examples)

puts "Accuracy: #{results.accuracy}"           # => 0.85
puts "Passed: #{results.passed_examples}"     # => 17
puts "Total: #{results.total_examples}"       # => 20
puts "Failed examples: #{results.failed_examples.count}"  # => 3
```

## Built-in Metrics

DSPy.rb includes common evaluation metrics out of the box:

```ruby
# Exact matching for precise comparisons
exact_metric = DSPy::Metrics.exact_match

# Fuzzy matching for text that might vary slightly
contains_metric = DSPy::Metrics.contains("key phrase")

# Numeric comparison with tolerance
numeric_metric = DSPy::Metrics.numeric_difference(tolerance: 0.1)

# Composite metrics for complex validation
composite_metric = DSPy::Metrics.composite_and(
  DSPy::Metrics.exact_match,
  DSPy::Metrics.contains("reasoning")
)
```

## Custom Metrics

Define domain-specific evaluation logic:

```ruby
# Custom metric for math problems
math_metric = proc do |example, prediction|
  # Check if the numerical answer is correct
  answer_correct = example.expected_values[:answer] == prediction[:answer]
  
  # Check if explanation mentions the operation
  problem = example.input_values[:problem]
  explanation = prediction[:explanation]
  
  has_operation = if problem.include?('+')
    explanation.include?('add') || explanation.include?('+')
  elsif problem.include?('-')
    explanation.include?('subtract') || explanation.include?('-')
  else
    true  # Other operations
  end
  
  answer_correct && has_operation
end

evaluator = DSPy::Evaluate.new(math_solver, metric: math_metric)
```

## Batch Evaluation and Performance Analysis

```ruby
# Evaluate with progress tracking
results = evaluator.evaluate(
  training_examples,
  display_progress: true,
  num_threads: 4  # Parallel evaluation
)

# Get detailed insights
puts "Average confidence: #{results.metrics[:average_confidence]}"
puts "Processing time: #{results.metrics[:total_duration_ms]}ms"

# Analyze failed cases
results.failed_examples.each do |failure|
  puts "Failed: #{failure.example.input_values[:problem]}"
  puts "Expected: #{failure.example.expected_values[:answer]}"
  puts "Got: #{failure.prediction[:answer]}"
  puts "Error: #{failure.error}" if failure.error
  puts "---"
end
```

## Example Validation and Matching

```ruby
example = training_examples.first

# Examples know how to validate predictions
prediction = { answer: 8, explanation: "5 + 3 = 8 apples total" }
puts example.matches_prediction?(prediction)  # => true

wrong_prediction = { answer: 7, explanation: "Wrong math" }
puts example.matches_prediction?(wrong_prediction)  # => false

# Get detailed validation information
validation = example.validate_prediction(prediction)
puts validation.valid?     # => true
puts validation.errors     # => []
```

## Evaluation Configuration

```ruby
# Configure evaluation behavior
evaluator = DSPy::Evaluate.new(
  program,
  metric: your_metric,
  num_threads: 4,        # Parallel processing
  max_errors: 5,         # Stop after 5 errors
  timeout: 30,           # 30 second timeout per example
  display_progress: true # Show progress bar
)

# Evaluation with custom configuration
config = DSPy::Evaluate::EvaluationConfig.new
config.batch_size = 10
config.retry_failed = true
config.collect_traces = true

results = evaluator.evaluate_with_config(examples, config)
```

## Integration with Optimization

Evaluation integrates seamlessly with optimization:

```ruby
# Use evaluation metric in optimization
optimizer = DSPy::Teleprompt::MIPROv2.new(
  metric: math_metric  # Same metric used for evaluation
)

result = optimizer.compile(
  math_solver,
  trainset: training_examples,
  valset: validation_examples
)

# Optimized program uses the same evaluation framework
optimized_results = evaluator.evaluate(validation_examples)
puts "Optimization improved accuracy from #{baseline} to #{optimized_results.accuracy}"
```

## Advanced Evaluation Patterns

### Multi-metric Evaluation

```ruby
# Evaluate on multiple metrics simultaneously
metrics = {
  accuracy: DSPy::Metrics.exact_match,
  reasoning_quality: proc { |ex, pred| pred[:explanation].length > 10 },
  contains_math: DSPy::Metrics.contains(/\d+/)
}

multi_evaluator = DSPy::Evaluate::MultiMetricEvaluator.new(program, metrics)
results = multi_evaluator.evaluate(examples)

puts "Accuracy: #{results[:accuracy].accuracy}"
puts "Reasoning Quality: #{results[:reasoning_quality].accuracy}"
```

### Cross-Validation

```ruby
# K-fold cross validation
cv_evaluator = DSPy::Evaluate::CrossValidator.new(
  program_class: -> { DSPy::ChainOfThought.new(MathWord) },
  metric: math_metric,
  folds: 5
)

cv_results = cv_evaluator.evaluate(all_examples)
puts "Mean accuracy: #{cv_results.mean_accuracy} ± #{cv_results.std_accuracy}"
```

## Next Steps

- Learn about [Prompt Optimization](prompt-optimization.md)
- Explore [MIPROv2 Optimizer](miprov2.md)
- Set up [Custom Metrics](../advanced/custom-metrics.md)