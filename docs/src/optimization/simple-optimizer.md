---
layout: docs
name: Simple Optimizer
description: Quick optimization with random search
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: Simple Optimizer
  url: "/optimization/simple-optimizer/"
prev:
  name: MIPROv2 Optimizer
  url: "/optimization/miprov2/"
next:
  name: Production
  url: "/production/"
date: 2025-07-10 00:00:00 +0000
---
# Simple Optimizer

The Simple Optimizer provides a straightforward approach to optimizing DSPy predictors through random search. It's ideal for quick experimentation, baseline establishment, and scenarios where you need fast results without the complexity of more advanced optimizers.

## Overview

The Simple Optimizer works by:
- **Random Search**: Generates random variations of instructions and few-shot examples
- **Trial-based Evaluation**: Tests each candidate configuration
- **Best Selection**: Returns the configuration with the highest score

Unlike MIPROv2's structured three-phase approach, Simple Optimizer uses a simpler random sampling strategy that can often find good solutions quickly.

## Basic Usage

### Quick Optimization

```ruby
# Define your signature
class ClassifyText < DSPy::Signature
  description "Classify the sentiment of the given text"
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, String
  end
end

# Create optimizer
optimizer = DSPy::SimpleOptimizer.new(signature: ClassifyText)

# Run optimization
result = optimizer.optimize(examples: training_examples) do |predictor, examples|
  # Your evaluation logic
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  evaluation_result = evaluator.evaluate(examples: examples) do |example|
    predictor.call(text: example.text)
  end
  evaluation_result.score
end

# Use results
best_predictor = result.optimized_program
puts "Best score: #{result.best_score_value}"
puts "Best instruction: #{best_predictor.prompt.instruction}"
```

### Custom Configuration

```ruby
# Configure optimizer parameters
config = DSPy::SimpleOptimizer::SimpleOptimizerConfig.new
config.max_trials = 50              # Number of random trials
config.initial_instruction_trials = 10  # Instructions to try first
config.max_few_shot_examples = 8    # Maximum few-shot examples

optimizer = DSPy::SimpleOptimizer.new(
  signature: ClassifyText,
  config: config
)
```

## Configuration Options

### SimpleOptimizerConfig Parameters

```ruby
config = DSPy::SimpleOptimizer::SimpleOptimizerConfig.new

# Trial settings
config.max_trials = 30                    # Total optimization trials
config.initial_instruction_trials = 5     # Instruction-only trials first
config.max_few_shot_examples = 6          # Max few-shot examples to include

# Example selection
config.example_selection_strategy = :random  # How to select examples

# Display
config.verbose = true                     # Show trial progress
```

## How It Works

### Optimization Process

The Simple Optimizer follows this process:

1. **Initial Instruction Trials**: Tests different instruction variations
2. **Bootstrap Generation**: Creates training examples using Chain of Thought
3. **Combined Trials**: Tests combinations of instructions and few-shot examples
4. **Best Selection**: Returns the highest-scoring configuration

### Random Search Strategy

```ruby
# The optimizer generates variations like:

# Different instructions:
# - "Classify the sentiment of this text"
# - "Determine if this text is positive, negative, or neutral"
# - "Analyze the emotional tone of the given text"

# Different few-shot combinations:
# - 0-6 randomly selected bootstrap examples
# - Various orderings of the same examples
```

## Working with Results

### SimpleOptimizerResult Object

```ruby
result = optimizer.optimize(examples: examples) do |predictor, val_examples|
  # evaluation logic
end

# Access basic results
puts "Best score: #{result.best_score_value}"
puts "Total trials: #{result.total_trials}"
puts "Optimization time: #{result.total_time}"

# Get the optimized predictor
optimized_predictor = result.optimized_program

# Access trial history
result.history[:trials].each do |trial|
  puts "Trial #{trial[:trial_number]}: #{trial[:score]}"
  puts "  Instruction: #{trial[:instruction][0..50]}..."
  puts "  Few-shot examples: #{trial[:few_shot_count]}"
end
```

### Best Configuration Details

```ruby
best_config = result.best_config

puts "Optimized instruction:"
puts best_config.instruction
puts
puts "Few-shot examples (#{best_config.few_shot_examples.size}):"
best_config.few_shot_examples.each_with_index do |example, i|
  puts "#{i+1}. Input: #{example.input}"
  puts "   Output: #{example.output}"
end
```

## Comparison with MIPROv2

### When to Use Simple Optimizer

```ruby
# Good for:
# - Quick experimentation and prototyping
# - Establishing baselines
# - Time-constrained optimization
# - Simple tasks with clear patterns

# Use Simple Optimizer when:
simple_optimizer = DSPy::SimpleOptimizer.new(signature: YourSignature)

# Use MIPROv2 when you need better results:
mipro_optimizer = DSPy::MIPROv2.new(signature: YourSignature, mode: :heavy)
```

### Performance Characteristics

```ruby
# Simple Optimizer:
# - Faster to run (fewer structured phases)
# - Good enough for many tasks
# - Less sophisticated instruction generation
# - Random search can miss optimal solutions

# MIPROv2:
# - More thorough optimization
# - Better instruction generation via grounded proposer
# - Structured bootstrap and selection phases
# - Generally better final performance
```

## Advanced Usage

### Custom Evaluation with Multiple Metrics

```ruby
result = optimizer.optimize(examples: training_examples) do |predictor, val_examples|
  accuracy_score = 0.0
  speed_score = 0.0
  
  val_examples.each do |example|
    start_time = Time.now
    prediction = predictor.call(text: example.text)
    duration = Time.now - start_time
    
    # Accuracy component
    if prediction.sentiment == example.expected_sentiment
      accuracy_score += 1.0
    end
    
    # Speed component (penalty for slow predictions)
    speed_penalty = [duration - 1.0, 0].max  # Penalty if > 1 second
    speed_score += (1.0 - speed_penalty * 0.1)
  end
  
  # Combined score (80% accuracy, 20% speed)
  total_examples = val_examples.size
  accuracy = accuracy_score / total_examples
  speed = speed_score / total_examples
  
  (accuracy * 0.8) + (speed * 0.2)
end
```

### Progressive Optimization

```ruby
# Start with Simple Optimizer for quick results
simple_optimizer = DSPy::SimpleOptimizer.new(signature: ClassifyText)
simple_result = simple_optimizer.optimize(examples: examples) do |predictor, val_examples|
  # evaluation logic
end

puts "Simple optimizer result: #{simple_result.best_score_value}"

# If results are promising, use MIPROv2 for refinement
if simple_result.best_score_value > 0.7
  mipro_optimizer = DSPy::MIPROv2.new(signature: ClassifyText, mode: :medium)
  mipro_result = mipro_optimizer.optimize(examples: examples) do |predictor, val_examples|
    # same evaluation logic
  end
  
  puts "MIPROv2 result: #{mipro_result.best_score_value}"
  
  # Use the better result
  final_result = mipro_result.best_score_value > simple_result.best_score_value ? 
                 mipro_result : simple_result
end
```

### Validation Split Strategy

```ruby
# Use separate validation for unbiased evaluation
result = optimizer.optimize(
  examples: training_examples,
  val_examples: validation_examples
) do |predictor, val_examples|
  # Evaluate on held-out validation set
  correct = 0
  val_examples.each do |example|
    prediction = predictor.call(text: example.text)
    correct += 1 if prediction.sentiment == example.expected_sentiment
  end
  correct.to_f / val_examples.size
end
```

## Integration with Storage

### Saving Optimization Results

```ruby
# Save the result
storage_manager = DSPy::Storage::StorageManager.new
saved_program = storage_manager.save_optimization_result(
  result,
  tags: ['simple_optimizer', 'baseline'],
  metadata: {
    optimizer: 'SimpleOptimizer',
    trials: result.total_trials,
    optimization_time: result.total_time
  }
)

puts "Saved with ID: #{saved_program.program_id}"
```

### Comparing with Previous Results

```ruby
# Load previous optimization results
previous_results = storage_manager.find_programs(
  optimizer: 'SimpleOptimizer',
  signature_class: 'ClassifyText'
)

current_score = result.best_score_value
previous_scores = previous_results.map { |r| r[:best_score] }.compact

if previous_scores.any?
  best_previous = previous_scores.max
  improvement = current_score - best_previous
  
  puts "Current score: #{current_score}"
  puts "Previous best: #{best_previous}"
  puts "Improvement: #{improvement > 0 ? '+' : ''}#{improvement.round(3)}"
else
  puts "First optimization for this signature"
end
```

## Monitoring and Debugging

### Progress Tracking

```ruby
config = DSPy::SimpleOptimizer::SimpleOptimizerConfig.new
config.verbose = true  # Show detailed progress

optimizer = DSPy::SimpleOptimizer.new(
  signature: ClassifyText,
  config: config
)

# Shows progress like:
# Trial 1/30: Instruction trial, Score: 0.75
# Trial 2/30: Instruction trial, Score: 0.82
# Trial 3/30: Bootstrap + Few-shot, Score: 0.79
# ...
# Best score so far: 0.89 (Trial 15)
```

### Result Analysis

```ruby
# Analyze trial results
trials = result.history[:trials]

# Find instruction-only trials
instruction_trials = trials.select { |t| t[:few_shot_count] == 0 }
best_instruction_score = instruction_trials.map { |t| t[:score] }.max

# Find few-shot trials
few_shot_trials = trials.select { |t| t[:few_shot_count] > 0 }
best_few_shot_score = few_shot_trials.map { |t| t[:score] }.max

puts "Best instruction-only score: #{best_instruction_score}"
puts "Best with few-shot examples: #{best_few_shot_score}"
puts "Few-shot improvement: #{best_few_shot_score - best_instruction_score}"
```

## Best Practices

### 1. Start Simple

```ruby
# Begin with default settings
optimizer = DSPy::SimpleOptimizer.new(signature: YourSignature)

# Adjust based on results
if result.best_score_value < target_score
  # Try more trials
  config = DSPy::SimpleOptimizer::SimpleOptimizerConfig.new
  config.max_trials = 100
  optimizer = DSPy::SimpleOptimizer.new(signature: YourSignature, config: config)
end
```

### 2. Use for Baselines

```ruby
# Establish baseline performance
baseline_optimizer = DSPy::SimpleOptimizer.new(signature: ClassifyText)
baseline_result = baseline_optimizer.optimize(examples: examples) do |predictor, val_examples|
  # evaluation logic
end

baseline_score = baseline_result.best_score_value
puts "Baseline score: #{baseline_score}"

# Set improvement targets for more advanced optimizers
target_improvement = 0.05  # 5% improvement target
target_score = baseline_score + target_improvement
```

### 3. Monitor Trial Diversity

```ruby
# Check if optimization is exploring diverse configurations
instructions = result.history[:trials].map { |t| t[:instruction] }.uniq
few_shot_configs = result.history[:trials].map { |t| t[:few_shot_count] }.uniq

puts "Unique instructions tried: #{instructions.size}"
puts "Few-shot configurations: #{few_shot_configs.sort}"

# If diversity is low, increase max_trials
if instructions.size < 10
  puts "Consider increasing trials for more exploration"
end
```

