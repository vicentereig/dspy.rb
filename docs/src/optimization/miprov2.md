---
layout: docs
name: MIPROv2 Optimizer
description: Advanced prompt optimization with MIPROv2
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: MIPROv2 Optimizer
  url: "/optimization/miprov2/"
prev:
  name: Prompt Optimization
  url: "/optimization/prompt-optimization/"
next:
  name: Simple Optimizer
  url: "/optimization/simple-optimizer/"
date: 2025-07-10 00:00:00 +0000
---
# MIPROv2 Optimizer

MIPROv2 (Multi-stage Instruction Proposal and Refinement Optimizer v2) is the primary optimization algorithm in DSPy.rb. It automatically improves your predictor's performance through a three-phase optimization process: bootstrap training, instruction optimization, and few-shot example refinement.

## Overview

MIPROv2 works by:
- **Bootstrap Phase**: Generating training examples with reasoning traces
- **Instruction Phase**: Optimizing the system instruction for better performance
- **Few-shot Phase**: Selecting the best combination of few-shot examples

The optimizer uses a grounded proposer to generate high-quality candidate instructions and sophisticated example selection to create optimal few-shot demonstrations.

## Basic Usage

### Simple Optimization

```ruby
# Define your signature
class ClassifyText < DSPy::Signature
  description "Classify the sentiment of the given text"
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, String
    const :confidence, Float
  end
end

# Create optimizer
optimizer = DSPy::MIPROv2.new(signature: ClassifyText)

# Run optimization
result = optimizer.optimize(examples: training_examples) do |predictor, examples|
  # Your evaluation logic
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  evaluation_result = evaluator.evaluate(examples: examples) do |example|
    predictor.call(text: example.text)
  end
  evaluation_result.score
end

# Use the optimized predictor
best_predictor = result.optimized_program
final_score = result.best_score_value

puts "Optimization complete!"
puts "Best score: #{final_score}"
puts "Best instruction: #{best_predictor.prompt.instruction}"
```

### AutoMode Configuration

MIPROv2 provides preset configurations for different optimization scenarios:

```ruby
# Light optimization - fastest, good for prototyping
optimizer = DSPy::MIPROv2.new(
  signature: ClassifyText,
  mode: :light
)

# Medium optimization - balanced performance and speed (default)
optimizer = DSPy::MIPROv2.new(
  signature: ClassifyText,
  mode: :medium
)

# Heavy optimization - most thorough, best results
optimizer = DSPy::MIPROv2.new(
  signature: ClassifyText,
  mode: :heavy
)
```

### Custom Configuration

```ruby
# Fine-tune optimization parameters
config = DSPy::MIPROv2::MIPROv2Config.new
config.bootstrap_examples = 4
config.max_bootstrap_examples = 8
config.num_candidate_instructions = 10
config.instruction_trials = 15
config.max_few_shot_examples = 6
config.few_shot_trials = 20

optimizer = DSPy::MIPROv2.new(
  signature: ClassifyText,
  config: config
)
```

## Configuration Options

### MIPROv2Config Parameters

```ruby
config = DSPy::MIPROv2::MIPROv2Config.new

# Bootstrap phase settings
config.bootstrap_examples = 4          # Examples to generate initially
config.max_bootstrap_examples = 8      # Maximum examples to collect

# Instruction optimization
config.num_candidate_instructions = 10 # Instruction variants to try
config.instruction_trials = 15         # Evaluation trials per instruction

# Few-shot optimization  
config.max_few_shot_examples = 6       # Max examples in final prompt
config.few_shot_trials = 20           # Trials for few-shot selection

# Example selection
config.example_selection_strategy = :random  # or :diverse

# Display options
config.verbose = true                  # Show optimization progress
```

### AutoMode Configurations

```ruby
# Light mode values:
# - bootstrap_examples: 2
# - max_bootstrap_examples: 4  
# - num_candidate_instructions: 5
# - instruction_trials: 8
# - max_few_shot_examples: 3
# - few_shot_trials: 10

# Medium mode values (default):
# - bootstrap_examples: 4
# - max_bootstrap_examples: 8
# - num_candidate_instructions: 10  
# - instruction_trials: 15
# - max_few_shot_examples: 6
# - few_shot_trials: 20

# Heavy mode values:
# - bootstrap_examples: 8
# - max_bootstrap_examples: 16
# - num_candidate_instructions: 20
# - instruction_trials: 25
# - max_few_shot_examples: 10
# - few_shot_trials: 30
```

## Optimization Phases

### Phase 1: Bootstrap Training

The optimizer generates high-quality training examples:

```ruby
# MIPROv2 automatically handles this, but you can observe the process
optimizer = DSPy::MIPROv2.new(
  signature: ClassifyText,
  config: config
)

# During optimization, bootstrap examples are generated using
# Chain of Thought reasoning to create examples with explanations
```

### Phase 2: Instruction Optimization

Multiple instruction candidates are generated and tested:

```ruby
# The grounded proposer generates instruction variations like:
# - "Classify the sentiment of the given text as positive, negative, or neutral."
# - "Analyze the emotional tone of the provided text and categorize it."
# - "Determine whether the text expresses positive, negative, or neutral sentiment."

# Each instruction is evaluated across multiple trials to find the best one
```

### Phase 3: Few-shot Example Selection

The best combination of few-shot examples is selected:

```ruby
# MIPROv2 tests different combinations of bootstrap examples
# to find the set that maximizes performance on validation data
```

## Working with Results

### MIPROv2Result Object

```ruby
result = optimizer.optimize(examples: examples) do |predictor, val_examples|
  # evaluation logic
end

# Access optimization results
puts "Best score: #{result.best_score_value}"
puts "Score name: #{result.best_score_name}"
puts "Total trials: #{result.total_trials}"

# Get the optimized predictor
optimized_predictor = result.optimized_program

# Access optimization history
result.history[:trials].each do |trial|
  puts "Trial #{trial[:trial_number]}: #{trial[:score]}"
end

# Check timing information
puts "Bootstrap time: #{result.history[:bootstrap_time]}"
puts "Instruction time: #{result.history[:instruction_time]}" 
puts "Few-shot time: #{result.history[:few_shot_time]}"
puts "Total time: #{result.total_time}"
```

### Best Configuration Access

```ruby
best_config = result.best_config

puts "Best instruction: #{best_config.instruction}"
puts "Number of few-shot examples: #{best_config.few_shot_examples.size}"

# Inspect few-shot examples
best_config.few_shot_examples.each_with_index do |example, i|
  puts "Example #{i+1}:"
  puts "  Input: #{example.input}"
  puts "  Output: #{example.output}"
end
```

## Integration with Storage and Registry

### Saving Optimization Results

```ruby
# Save to storage system
storage = DSPy::Storage::StorageManager.new
saved_program = storage.save_optimization_result(
  result,
  metadata: {
    signature: 'text_classifier',
    optimization_method: 'MIPROv2',
    mode: 'medium'
  }
)

puts "Saved with ID: #{saved_program.program_id}"
```

### Integration with Registry

```ruby
# Auto-register with registry
registry_manager = DSPy::Registry::RegistryManager.new
registry_manager.integration_config.auto_register_optimizations = true

# This will automatically register the result
version = registry_manager.register_optimization_result(
  result,
  signature_name: 'text_classifier'
)

puts "Registered as version: #{version.version}"
```

## Advanced Usage

### Custom Evaluation Logic

```ruby
result = optimizer.optimize(examples: training_examples) do |predictor, val_examples|
  total_score = 0.0
  
  val_examples.each do |example|
    prediction = predictor.call(text: example.text)
    
    # Custom scoring logic
    if prediction.sentiment == example.expected_sentiment
      # Base score for correct classification
      score = 1.0
      
      # Bonus for high confidence on correct predictions
      if prediction.confidence > 0.8
        score += 0.2
      end
      
      total_score += score
    end
  end
  
  total_score / val_examples.size
end
```

### Validation Split

```ruby
# Use separate validation set for unbiased evaluation
result = optimizer.optimize(
  examples: training_examples,
  val_examples: validation_examples
) do |predictor, val_examples|
  # Evaluation on held-out validation set
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  evaluator.evaluate(examples: val_examples) do |example|
    predictor.call(text: example.text)
  end.score
end
```

### Monitoring Progress

```ruby
config = DSPy::MIPROv2::MIPROv2Config.new
config.verbose = true  # Show detailed progress

optimizer = DSPy::MIPROv2.new(
  signature: ClassifyText,
  config: config
)

# Progress information is printed during optimization:
# - Bootstrap phase progress
# - Instruction candidate evaluation
# - Few-shot selection progress
# - Best scores and configurations
```

## Best Practices

### 1. Choose Appropriate Mode

```ruby
# For quick experimentation
optimizer = DSPy::MIPROv2.new(signature: YourSignature, mode: :light)

# For production optimization
optimizer = DSPy::MIPROv2.new(signature: YourSignature, mode: :heavy)

# For balanced optimization
optimizer = DSPy::MIPROv2.new(signature: YourSignature, mode: :medium)
```

### 2. Provide Quality Examples

```ruby
# Use diverse, high-quality training examples
training_examples = [
  DSPy::Example.new(
    text: "I love this product! It's amazing.",
    expected_sentiment: "positive"
  ),
  DSPy::Example.new(
    text: "This is the worst experience I've ever had.",
    expected_sentiment: "negative"
  ),
  DSPy::Example.new(
    text: "The product is okay, nothing special.",
    expected_sentiment: "neutral"
  )
  # ... more diverse examples
]
```

### 3. Robust Evaluation

```ruby
result = optimizer.optimize(examples: examples) do |predictor, val_examples|
  total_correct = 0
  total_attempted = 0
  
  val_examples.each do |example|
    begin
      prediction = predictor.call(text: example.text)
      total_attempted += 1
      
      if prediction.sentiment.downcase == example.expected_sentiment.downcase
        total_correct += 1
      end
    rescue => e
      # Handle prediction errors gracefully
      puts "Prediction failed: #{e.message}"
    end
  end
  
  return 0.0 if total_attempted == 0
  total_correct.to_f / total_attempted
end
```

### 4. Save Your Results

```ruby
# Always save successful optimizations
if result.best_score_value > 0.8  # Your quality threshold
  storage_manager = DSPy::Storage::StorageManager.new
  storage_manager.save_optimization_result(
    result,
    tags: ['production', 'validated'],
    metadata: {
      dataset: 'customer_reviews_v2',
      optimization_date: Date.current,
      minimum_score: 0.8
    }
  )
end
```

