# Simple Optimizer

The Simple Optimizer provides lightweight prompt optimization through random search and grid search methods. It's perfect for quick experimentation, prototyping, and scenarios where you need fast optimization with minimal computational resources.

## Overview

The Simple Optimizer offers two main strategies:
- **Random Search**: Randomly samples from the prompt configuration space
- **Grid Search**: Systematically explores predefined parameter combinations
- **Hybrid Search**: Combines random and grid search for balanced exploration

## Basic Usage

### Random Search

```ruby
class ClassifyText < DSPy::Signature
  description "Classify text sentiment"
  
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

# Prepare examples
examples = [
  DSPy::Example.new(
    inputs: { text: "I love this!" },
    outputs: { sentiment: ClassifyText::Sentiment::Positive, confidence: 0.9 }
  ),
  # ... more examples
]

# Initialize simple optimizer with random search
optimizer = DSPy::SimpleOptimizer.new(
  signature: ClassifyText,
  strategy: :random_search,
  num_trials: 50,
  metric: DSPy::Metrics::Accuracy.new
)

# Run optimization
result = optimizer.optimize(examples: examples)

# Use optimized predictor
optimized_predictor = result.best_predictor
puts optimized_predictor.call(text: "This is great!")
```

### Grid Search

```ruby
# Define parameter grid
parameter_grid = {
  temperature: [0.0, 0.3, 0.7, 1.0],
  max_tokens: [50, 100, 200],
  instruction_style: [:concise, :detailed, :examples_heavy],
  few_shot_count: [0, 3, 5, 8]
}

# Initialize with grid search
optimizer = DSPy::SimpleOptimizer.new(
  signature: ClassifyText,
  strategy: :grid_search,
  parameter_grid: parameter_grid,
  metric: DSPy::Metrics::F1Score.new
)

result = optimizer.optimize(examples: examples)

puts "Best parameters: #{result.best_parameters}"
puts "Best score: #{result.best_score}"
```

## Configuration Options

### Basic Configuration

```ruby
optimizer = DSPy::SimpleOptimizer.new(
  signature: YourSignature,
  strategy: :random_search,           # :random_search, :grid_search, :hybrid
  num_trials: 30,                     # Number of configurations to try
  metric: DSPy::Metrics::Accuracy.new, # Evaluation metric
  early_stopping: true,               # Stop early if no improvement
  patience: 5,                        # Trials without improvement before stopping
  random_seed: 42                     # For reproducible results
)
```

### Advanced Configuration

```ruby
optimizer = DSPy::SimpleOptimizer.new(
  signature: ComplexTask,
  strategy: :hybrid,
  
  # Search space configuration
  search_space: {
    # LLM parameters
    temperature: { type: :continuous, range: [0.0, 1.0] },
    top_p: { type: :continuous, range: [0.8, 1.0] },
    max_tokens: { type: :discrete, values: [50, 100, 200, 500] },
    
    # Prompt parameters
    instruction_length: { type: :discrete, values: [:short, :medium, :long] },
    instruction_tone: { type: :categorical, values: [:formal, :casual, :technical] },
    
    # Few-shot parameters
    num_examples: { type: :discrete, values: [0, 2, 4, 6, 8] },
    example_selection: { type: :categorical, values: [:random, :diverse, :similar] }
  },
  
  # Multi-objective optimization
  metrics: {
    primary: DSPy::Metrics::Accuracy.new,
    secondary: DSPy::Metrics::Latency.new,
    weights: [0.8, 0.2]  # Weight for combining metrics
  },
  
  # Resource constraints
  max_time: 30.minutes,
  max_cost: 10.0,  # Dollars
  parallel_trials: 4  # Run trials in parallel
)
```

## Search Strategies

### Random Search Details

Random search is effective for high-dimensional spaces and unknown parameter relationships:

```ruby
class RandomSearchOptimizer < DSPy::SimpleOptimizer
  def initialize(signature, search_space: {}, **options)
    @search_space = search_space
    super(signature, strategy: :random_search, **options)
  end
  
  def sample_configuration
    config = {}
    
    @search_space.each do |param, space_def|
      config[param] = case space_def[:type]
      when :continuous
        rand * (space_def[:range][1] - space_def[:range][0]) + space_def[:range][0]
      when :discrete
        space_def[:values].sample
      when :categorical
        space_def[:values].sample
      end
    end
    
    config
  end
end

# Usage
optimizer = RandomSearchOptimizer.new(
  ClassifyText,
  search_space: {
    temperature: { type: :continuous, range: [0.0, 1.0] },
    instruction_style: { type: :categorical, values: [:brief, :detailed, :examples] },
    few_shot_count: { type: :discrete, values: [0, 3, 5, 8] }
  },
  num_trials: 100
)
```

### Grid Search Details

Grid search systematically explores all parameter combinations:

```ruby
class GridSearchOptimizer < DSPy::SimpleOptimizer
  def initialize(signature, parameter_grid: {}, **options)
    @parameter_grid = parameter_grid
    @all_combinations = generate_combinations(parameter_grid)
    super(signature, strategy: :grid_search, **options)
  end
  
  def total_combinations
    @all_combinations.size
  end
  
  private
  
  def generate_combinations(grid)
    keys = grid.keys
    values = grid.values
    
    values.first.product(*values[1..-1]).map do |combination|
      keys.zip(combination).to_h
    end
  end
end

# Usage with comprehensive grid
comprehensive_grid = {
  temperature: [0.0, 0.2, 0.5, 0.8, 1.0],
  max_tokens: [50, 100, 200],
  top_p: [0.9, 0.95, 1.0],
  instruction_format: [:standard, :chain_of_thought, :few_shot],
  example_count: [0, 2, 4, 6]
}

optimizer = GridSearchOptimizer.new(
  ClassifyText,
  parameter_grid: comprehensive_grid
)

puts "Total combinations to explore: #{optimizer.total_combinations}"
```

### Hybrid Search

Combines the efficiency of grid search with the exploration of random search:

```ruby
optimizer = DSPy::SimpleOptimizer.new(
  signature: YourSignature,
  strategy: :hybrid,
  
  # Grid search for key parameters
  core_grid: {
    temperature: [0.0, 0.5, 1.0],
    instruction_style: [:brief, :detailed]
  },
  
  # Random search for fine-tuning
  random_parameters: {
    top_p: { type: :continuous, range: [0.8, 1.0] },
    max_tokens: { type: :discrete, values: [50, 75, 100, 150, 200] }
  },
  
  grid_trials_ratio: 0.3  # 30% grid search, 70% random search
)
```

## Example Selection Optimization

### Dynamic Example Selection

```ruby
class ExampleAwareOptimizer < DSPy::SimpleOptimizer
  def optimize(examples:, **options)
    # Split examples for selection optimization
    example_pool, eval_examples = split_examples(examples, ratio: 0.8)
    
    best_score = 0.0
    best_config = nil
    
    @num_trials.times do |trial|
      # Sample configuration
      config = sample_configuration
      
      # Select examples based on configuration
      selected_examples = select_examples(example_pool, config)
      
      # Create predictor with selected examples and config
      predictor = create_predictor(config, selected_examples)
      
      # Evaluate on held-out examples
      score = evaluate_predictor(predictor, eval_examples)
      
      if score > best_score
        best_score = score
        best_config = config.merge(selected_examples: selected_examples)
      end
    end
    
    SimpleOptimizerResult.new(
      best_configuration: best_config,
      best_score: best_score,
      optimization_history: @history
    )
  end
  
  private
  
  def select_examples(pool, config)
    selection_strategy = config[:example_selection] || :random
    count = config[:example_count] || 5
    
    case selection_strategy
    when :random
      pool.sample(count)
    when :diverse
      select_diverse_examples(pool, count)
    when :similar_to_eval
      select_representative_examples(pool, count)
    end
  end
  
  def select_diverse_examples(pool, count)
    # Use clustering or similarity metrics to select diverse examples
    return pool.sample(count) if pool.size <= count
    
    selected = [pool.sample]  # Start with random example
    remaining = pool - selected
    
    (count - 1).times do
      # Select example most different from already selected
      next_example = remaining.max_by do |candidate|
        min_similarity_to_selected = selected.map do |selected_ex|
          calculate_similarity(candidate, selected_ex)
        end.min
        
        min_similarity_to_selected
      end
      
      selected << next_example
      remaining -= [next_example]
    end
    
    selected
  end
end
```

## Optimization Callbacks and Monitoring

### Progress Tracking

```ruby
optimizer = DSPy::SimpleOptimizer.new(
  signature: YourSignature,
  strategy: :random_search,
  num_trials: 100
)

# Track optimization progress
result = optimizer.optimize(
  examples: examples,
  callbacks: {
    on_trial_start: ->(trial_num, config) {
      puts "Starting trial #{trial_num} with config: #{config}"
    },
    
    on_trial_complete: ->(trial_num, score, config) {
      puts "Trial #{trial_num} score: #{score}"
    },
    
    on_improvement: ->(old_best, new_best, improvement) {
      puts "New best score: #{new_best} (improvement: +#{improvement})"
    },
    
    on_early_stop: ->(trial_num, reason) {
      puts "Early stopping at trial #{trial_num}: #{reason}"
    }
  }
)
```

### Custom Evaluation

```ruby
class CustomEvaluationOptimizer < DSPy::SimpleOptimizer
  def evaluate_configuration(predictor, examples, config)
    # Standard accuracy evaluation
    accuracy = super(predictor, examples, config)
    
    # Additional custom metrics
    latency = measure_average_latency(predictor, examples)
    cost = estimate_cost(config, examples.size)
    
    # Combine metrics with weights
    combined_score = (
      0.6 * accuracy +
      0.3 * (1.0 - normalize_latency(latency)) +
      0.1 * (1.0 - normalize_cost(cost))
    )
    
    {
      accuracy: accuracy,
      latency: latency,
      cost: cost,
      combined_score: combined_score
    }
  end
  
  private
  
  def measure_average_latency(predictor, examples)
    latencies = examples.sample(10).map do |example|
      start_time = Time.current
      predictor.call(example.inputs)
      Time.current - start_time
    end
    
    latencies.sum / latencies.size
  end
  
  def estimate_cost(config, num_examples)
    base_cost = 0.001  # Base cost per call
    token_multiplier = config[:max_tokens] / 100.0
    
    base_cost * token_multiplier * num_examples
  end
end
```

## Results Analysis

### Accessing Results

```ruby
result = optimizer.optimize(examples: examples)

# Best configuration and performance
puts "Best score: #{result.best_score}"
puts "Best configuration: #{result.best_configuration}"

# Access optimization history
result.optimization_history.each_with_index do |trial, i|
  puts "Trial #{i}: #{trial[:score]} (config: #{trial[:configuration]})"
end

# Performance analysis
analysis = result.analyze_performance
puts "Average score: #{analysis[:average_score]}"
puts "Score std dev: #{analysis[:score_std_dev]}"
puts "Best parameters: #{analysis[:best_parameters]}"
```

### Parameter Importance Analysis

```ruby
class ParameterImportanceAnalyzer
  def initialize(optimization_history)
    @history = optimization_history
  end
  
  def analyze_parameter_importance
    parameter_effects = {}
    
    # Group trials by parameter values
    @history.group_by { |trial| trial[:configuration] }.each do |config, trials|
      config.each do |param, value|
        parameter_effects[param] ||= {}
        parameter_effects[param][value] ||= []
        parameter_effects[param][value] += trials.map { |t| t[:score] }
      end
    end
    
    # Calculate importance scores
    importance_scores = {}
    parameter_effects.each do |param, value_scores|
      scores_by_value = value_scores.transform_values { |scores| scores.sum / scores.size }
      
      importance_scores[param] = {
        variance: calculate_variance(scores_by_value.values),
        best_value: scores_by_value.max_by { |value, score| score }.first,
        effect_size: scores_by_value.values.max - scores_by_value.values.min
      }
    end
    
    importance_scores.sort_by { |param, stats| -stats[:effect_size] }
  end
end

# Usage
analyzer = ParameterImportanceAnalyzer.new(result.optimization_history)
importance = analyzer.analyze_parameter_importance

puts "Parameter importance (by effect size):"
importance.each do |param, stats|
  puts "#{param}: #{stats[:effect_size].round(3)} (best: #{stats[:best_value]})"
end
```

## Integration with Other Optimizers

### Warm Start from Simple Optimizer

```ruby
# Use simple optimizer for quick exploration
simple_optimizer = DSPy::SimpleOptimizer.new(
  signature: YourSignature,
  strategy: :random_search,
  num_trials: 20
)

simple_result = simple_optimizer.optimize(examples: examples)

# Use best configuration as starting point for MIPROv2
advanced_optimizer = DSPy::MIPROv2.new(
  signature: YourSignature,
  warm_start_config: simple_result.best_configuration
)

advanced_result = advanced_optimizer.optimize(examples: examples)
```

### Ensemble with Multiple Simple Optimizers

```ruby
class EnsembleSimpleOptimizer
  def initialize(signature, num_optimizers: 5)
    @signature = signature
    @optimizers = num_optimizers.times.map do |i|
      DSPy::SimpleOptimizer.new(
        signature: signature,
        strategy: [:random_search, :grid_search].sample,
        random_seed: i * 100  # Different seeds for diversity
      )
    end
  end
  
  def optimize(examples:)
    # Run each optimizer
    results = @optimizers.map do |optimizer|
      optimizer.optimize(examples: examples)
    end
    
    # Combine best predictors into ensemble
    best_predictors = results.map(&:best_predictor)
    
    EnsembleResult.new(
      individual_results: results,
      ensemble_predictor: create_ensemble(best_predictors),
      diversity_score: calculate_ensemble_diversity(best_predictors)
    )
  end
end
```

## Best Practices

### 1. Start Simple

```ruby
# Begin with broad random search
initial_optimizer = DSPy::SimpleOptimizer.new(
  signature: YourSignature,
  strategy: :random_search,
  num_trials: 50,
  search_space: broad_search_space
)

initial_result = initial_optimizer.optimize(examples: examples)

# Refine with focused grid search
refined_optimizer = DSPy::SimpleOptimizer.new(
  signature: YourSignature,
  strategy: :grid_search,
  parameter_grid: create_focused_grid(initial_result.best_configuration)
)
```

### 2. Use Appropriate Search Space

```ruby
# Good: Reasonable ranges
search_space = {
  temperature: { type: :continuous, range: [0.0, 1.0] },
  max_tokens: { type: :discrete, values: [50, 100, 200, 400] },
  instruction_style: { type: :categorical, values: [:brief, :detailed, :examples] }
}

# Bad: Too broad or impractical
bad_search_space = {
  temperature: { type: :continuous, range: [-10.0, 10.0] },  # Invalid range
  max_tokens: { type: :discrete, values: (1..10000).to_a },  # Too many options
  instruction_style: { type: :categorical, values: [:a, :b, :c, :d, :e, :f] }  # Too many variants
}
```

### 3. Monitor Resource Usage

```ruby
optimizer = DSPy::SimpleOptimizer.new(
  signature: YourSignature,
  strategy: :random_search,
  num_trials: 100,
  
  # Set reasonable limits
  max_time: 30.minutes,
  max_cost: 5.0,
  early_stopping: true,
  patience: 10
)
```

The Simple Optimizer is perfect for getting started with optimization, prototyping new approaches, and scenarios where you need quick results with minimal computational overhead.