# MIPROv2 Optimizer

MIPROv2 (Multi-prompt Instruction Proposal and Refinement Optimizer v2) is DSPy.rb's state-of-the-art automatic prompt optimization algorithm. It systematically explores the prompt space to find optimal instructions and examples for your signatures.

## Overview

MIPROv2 optimizes prompts through multiple strategies:
- **Instruction Generation**: Creates and refines task instructions
- **Example Selection**: Finds the most effective few-shot examples  
- **Multi-prompt Ensembling**: Combines multiple optimized prompts
- **Bootstrapping**: Generates synthetic training data
- **Bayesian Optimization**: Efficiently explores the optimization space

## Basic Usage

```ruby
class ClassifySentiment < DSPy::Signature
  description "Classify the sentiment of customer feedback"
  
  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative') 
      Neutral = new('neutral')
    end
  end
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

# Prepare training examples
examples = [
  DSPy::Example.new(
    inputs: { text: "I love this product!" },
    outputs: { sentiment: ClassifySentiment::Sentiment::Positive, confidence: 0.9 }
  ),
  DSPy::Example.new(
    inputs: { text: "Terrible customer service" },
    outputs: { sentiment: ClassifySentiment::Sentiment::Negative, confidence: 0.85 }
  ),
  # ... more examples
]

# Initialize and run optimizer
optimizer = DSPy::MIPROv2.new(
  signature: ClassifySentiment,
  metric: DSPy::Metrics::Accuracy.new,
  num_candidates: 10,
  init_temperature: 1.0
)

# Optimize with examples
result = optimizer.optimize(
  examples: examples,
  max_iterations: 20,
  patience: 3
)

# Use optimized predictor
optimized_predictor = result.best_predictor
puts optimized_predictor.call(text: "This is amazing!")
```

## Configuration Options

### Basic Configuration

```ruby
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  metric: DSPy::Metrics::F1Score.new,          # Evaluation metric
  num_candidates: 15,                          # Number of prompt candidates to generate
  init_temperature: 0.8,                       # Initial exploration temperature
  max_examples_per_demo: 5,                   # Max few-shot examples per prompt
  bootstrap_examples: true,                    # Generate synthetic examples
  ensemble_size: 3                            # Number of prompts in final ensemble
)
```

### Advanced Configuration

```ruby
optimizer = DSPy::MIPROv2.new(
  signature: ComplexTask,
  metric: DSPy::Metrics::CustomMetric.new(
    accuracy_weight: 0.7,
    latency_weight: 0.3
  ),
  
  # Instruction optimization
  instruction_candidates: 20,
  instruction_refinement_steps: 3,
  
  # Example selection
  example_selection_strategy: :diversity_based,
  max_bootstrap_examples: 100,
  
  # Bayesian optimization
  acquisition_function: :expected_improvement,
  exploration_weight: 0.1,
  
  # Multi-objective optimization
  objectives: [:accuracy, :latency, :cost],
  pareto_front_size: 10,
  
  # Resource constraints
  max_lm_calls: 500,
  max_optimization_time: 30.minutes
)
```

## Optimization Strategies

### Instruction Generation

MIPROv2 automatically generates and refines task instructions:

```ruby
# The optimizer will generate instruction variants like:
instructions = [
  "Carefully analyze the sentiment expressed in the following text",
  "Determine if the customer feedback is positive, negative, or neutral",
  "Classify the emotional tone of this customer review",
  "Evaluate the sentiment conveyed in the provided text"
]

# Each instruction is tested and refined based on performance
refined_instruction = optimizer.refine_instruction(
  base_instruction: "Classify sentiment",
  examples: training_examples,
  refinement_steps: 3
)
```

### Example Selection and Bootstrapping

```ruby
# Configure example optimization
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  
  # Example selection strategy
  example_selection: {
    strategy: :coverage_based,        # :random, :diversity_based, :coverage_based
    max_examples: 8,
    diversity_threshold: 0.7
  },
  
  # Bootstrapping configuration
  bootstrapping: {
    enabled: true,
    target_examples: 200,
    quality_threshold: 0.8,
    iterations: 5
  }
)

# Access selected examples after optimization
result = optimizer.optimize(examples: examples)
puts "Selected examples: #{result.selected_examples.size}"
puts "Generated examples: #{result.bootstrapped_examples.size}"
```

### Multi-prompt Ensembling

```ruby
# Configure ensemble optimization
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  
  # Ensemble configuration
  ensemble: {
    size: 5,                          # Number of prompts in ensemble
    combination_strategy: :weighted,   # :majority_vote, :weighted, :confidence_based
    diversity_penalty: 0.1            # Encourage diverse prompts
  }
)

result = optimizer.optimize(examples: examples)

# The result contains an ensemble predictor
ensemble_predictor = result.ensemble_predictor

# Individual prompts are also available
individual_predictors = result.individual_predictors
individual_predictors.each_with_index do |predictor, i|
  puts "Prompt #{i} performance: #{predictor.validation_score}"
end
```

## Monitoring Optimization Progress

### Progress Callbacks

```ruby
optimizer = DSPy::MIPROv2.new(signature: YourSignature)

# Add progress monitoring
result = optimizer.optimize(
  examples: examples,
  callbacks: {
    on_iteration: ->(iteration, best_score, current_candidate) {
      puts "Iteration #{iteration}: Best score = #{best_score}"
      puts "Current candidate performance: #{current_candidate.score}"
    },
    
    on_improvement: ->(old_score, new_score, improvement) {
      puts "Improvement found: #{old_score} → #{new_score} (+#{improvement})"
    },
    
    on_completion: ->(final_result) {
      puts "Optimization completed in #{final_result.total_time} seconds"
      puts "Final score: #{final_result.best_score}"
    }
  }
)
```

### Real-time Metrics

```ruby
# Enable detailed metrics collection
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  collect_metrics: true,
  metrics_interval: 5  # Report every 5 iterations
)

result = optimizer.optimize(examples: examples)

# Access optimization metrics
metrics = result.optimization_metrics
puts "Total LM calls: #{metrics.total_lm_calls}"
puts "Average iteration time: #{metrics.avg_iteration_time}"
puts "Convergence iteration: #{metrics.convergence_iteration}"

# Plot optimization progress
metrics.plot_progress  # Requires plotting library
```

## Custom Metrics

### Define Custom Evaluation Metrics

```ruby
class BusinessMetric < DSPy::Metrics::Base
  def initialize(cost_per_error: 10.0, cost_per_call: 0.01)
    @cost_per_error = cost_per_error
    @cost_per_call = cost_per_call
  end
  
  def evaluate(predictions, ground_truth)
    correct = 0
    total_cost = predictions.size * @cost_per_call
    
    predictions.zip(ground_truth).each do |pred, truth|
      if pred.matches?(truth)
        correct += 1
      else
        total_cost += @cost_per_error
      end
    end
    
    accuracy = correct.to_f / predictions.size
    roi = accuracy / total_cost  # Return on investment
    
    {
      accuracy: accuracy,
      total_cost: total_cost,
      roi: roi,
      score: roi  # Primary optimization target
    }
  end
end

# Use custom metric in optimization
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  metric: BusinessMetric.new(cost_per_error: 15.0)
)
```

### Multi-objective Optimization

```ruby
class MultiObjectiveMetric < DSPy::Metrics::Base
  def evaluate(predictions, ground_truth)
    accuracy = calculate_accuracy(predictions, ground_truth)
    latency = calculate_average_latency(predictions)
    cost = calculate_total_cost(predictions)
    
    # Normalize metrics to 0-1 scale
    normalized_accuracy = accuracy
    normalized_latency = 1.0 - (latency / max_acceptable_latency)
    normalized_cost = 1.0 - (cost / max_acceptable_cost)
    
    # Weighted combination
    score = (0.5 * normalized_accuracy + 
             0.3 * normalized_latency + 
             0.2 * normalized_cost)
    
    {
      accuracy: accuracy,
      latency: latency,
      cost: cost,
      score: score,
      pareto_metrics: [accuracy, -latency, -cost]  # For Pareto optimization
    }
  end
end
```

## Advanced Features

### Distributed Optimization

```ruby
# Configure distributed optimization across multiple workers
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  
  # Distributed configuration
  distributed: {
    enabled: true,
    num_workers: 4,
    worker_timeout: 300,
    coordinator_host: 'localhost:8080'
  }
)

# Optimization will automatically distribute across workers
result = optimizer.optimize(examples: examples)
```

### Incremental Optimization

```ruby
# Load previous optimization state
previous_result = DSPy::Storage.load_optimization_result('optimization_v1')

# Continue optimization from previous state
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  warm_start: previous_result  # Start from previous best
)

# Add new examples and continue optimizing
new_examples = load_new_training_data
all_examples = previous_result.training_examples + new_examples

incremental_result = optimizer.optimize(
  examples: all_examples,
  max_iterations: 10  # Few additional iterations
)
```

### Optimization with Constraints

```ruby
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  
  # Resource constraints
  constraints: {
    max_prompt_length: 2000,           # Characters
    max_examples_per_prompt: 5,        # Few-shot examples
    max_lm_calls_per_candidate: 10,    # Evaluation budget
    required_accuracy: 0.85,           # Minimum acceptable accuracy
    max_latency: 2.0,                  # Seconds
    max_cost_per_prediction: 0.05      # Dollars
  }
)

result = optimizer.optimize(examples: examples)

# Check if constraints were satisfied
if result.constraints_satisfied?
  puts "All constraints satisfied!"
else
  puts "Constraint violations: #{result.constraint_violations}"
end
```

## Optimization Results

### Accessing Results

```ruby
result = optimizer.optimize(examples: examples)

# Best performing predictor
best_predictor = result.best_predictor
best_score = result.best_score

# Optimization metadata
puts "Optimization took #{result.total_time} seconds"
puts "Explored #{result.candidates_evaluated} candidates"
puts "Best score: #{result.best_score}"

# Access the optimized prompt
optimized_prompt = result.best_prompt
puts "Optimized instruction: #{optimized_prompt.instruction}"
puts "Selected examples: #{optimized_prompt.examples.size}"

# Performance breakdown
performance = result.performance_breakdown
puts "Training accuracy: #{performance[:train_accuracy]}"
puts "Validation accuracy: #{performance[:validation_accuracy]}"
puts "Test accuracy: #{performance[:test_accuracy]}"
```

### Saving and Loading Results

```ruby
# Save optimization result
DSPy::Storage.save_optimization_result(result, 'sentiment_classifier_v2')

# Load and use later
saved_result = DSPy::Storage.load_optimization_result('sentiment_classifier_v2')
optimized_predictor = saved_result.best_predictor

# Use in production
production_result = optimized_predictor.call(text: "Customer feedback text")
```

## Integration with Other Components

### Registry Integration

```ruby
# Automatically register optimized signatures
optimizer = DSPy::MIPROv2.new(
  signature: ClassifySentiment,
  auto_register: true,
  registry_name: 'sentiment_classifier_optimized'
)

result = optimizer.optimize(examples: examples)

# Optimized signature is automatically registered
optimized_classifier = DSPy::Registry.get_signature('sentiment_classifier_optimized')
```

### Evaluation Integration

```ruby
# Use with evaluation framework
evaluator = DSPy::Evaluate.new(
  examples: test_examples,
  metric: DSPy::Metrics::Accuracy.new
)

# Evaluate baseline
baseline_predictor = DSPy::Predict.new(ClassifySentiment)
baseline_score = evaluator.evaluate(baseline_predictor)

# Optimize and evaluate
optimizer = DSPy::MIPROv2.new(signature: ClassifySentiment)
result = optimizer.optimize(examples: train_examples)

optimized_score = evaluator.evaluate(result.best_predictor)

puts "Baseline accuracy: #{baseline_score}"
puts "Optimized accuracy: #{optimized_score}"
puts "Improvement: #{optimized_score - baseline_score}"
```

## Best Practices

### 1. Quality Training Data

```ruby
# Ensure high-quality, diverse examples
examples = ExampleQualityAssessor.new(YourSignature)
  .filter_high_quality(raw_examples, threshold: 0.8)

# Balance across output categories
balanced_examples = ExampleBalancer.new
  .balance_by_output(examples, target_per_category: 50)

optimizer = DSPy::MIPROv2.new(signature: YourSignature)
result = optimizer.optimize(examples: balanced_examples)
```

### 2. Iterative Optimization

```ruby
# Start with smaller datasets for quick iterations
initial_examples = examples.sample(100)
quick_result = DSPy::MIPROv2.new(
  signature: YourSignature,
  num_candidates: 5,
  max_iterations: 10
).optimize(examples: initial_examples)

# Scale up with promising configuration
full_result = DSPy::MIPROv2.new(
  signature: YourSignature,
  num_candidates: 20,
  max_iterations: 50,
  warm_start: quick_result
).optimize(examples: examples)
```

### 3. Monitor Resource Usage

```ruby
# Set reasonable resource limits
optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  max_lm_calls: 1000,           # Prevent runaway costs
  max_optimization_time: 1.hour, # Time budget
  early_stopping: {
    patience: 5,                # Stop if no improvement
    min_delta: 0.01            # Minimum improvement threshold
  }
)
```

MIPROv2 is a powerful tool for automatic prompt optimization. Start with simple configurations and gradually explore advanced features as you become familiar with the optimization process.