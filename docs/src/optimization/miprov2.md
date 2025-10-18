---
layout: docs
title: "MIPROv2 Ruby: Automated Prompt Engineering That Beats Manual Tuning"
name: MIPROv2 Optimizer
description: "Cut prompt optimization time by 80% with MIPROv2. Automatic instruction generation, few-shot learning, and performance benchmarks for Ruby developers."
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: MIPROv2 Optimizer
  url: "/optimization/miprov2/"
prev:
  name: Prompt Optimization
  url: "/optimization/prompt-optimization/"
next:
  name: GEPA Optimizer
  url: "/optimization/gepa/"
date: 2025-07-10 00:00:00 +0000
---
# MIPROv2 Optimizer

MIPROv2 (Multi-prompt Instruction Proposal with Retrieval Optimization v2) is the state-of-the-art prompt optimization algorithm in DSPy.rb. It combines bootstrap sampling, instruction generation, and advanced Bayesian optimization to automatically improve your predictor's performance through a sophisticated three-phase optimization process.

## Overview

MIPROv2 works by:
- **Bootstrap Phase**: Generating high-quality few-shot examples with reasoning traces using multiple bootstrap sets
- **Instruction Proposal Phase**: Using a grounded proposer to generate multiple candidate instructions tailored to your task
- **Bayesian Optimization Phase**: Intelligently exploring candidate configurations (instruction + few-shot combinations) using Gaussian Processes for optimal selection

The optimizer provides three optimization strategies: greedy (fastest), adaptive (balanced exploration/exploitation), and Bayesian (most sophisticated with GP-based candidate selection).

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

# Create program to optimize
program = DSPy::Predict.new(ClassifyText)

# Create optimizer with custom metric
metric = proc do |example, prediction|
  # Return true/false for pass/fail evaluation
  prediction.sentiment.downcase == example.expected_sentiment.downcase
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)

# Run optimization
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)

# Use the optimized predictor
best_program = result.optimized_program
final_score = result.best_score_value

puts "Optimization complete!"
puts "Best score: #{final_score}"
puts "Best instruction: #{best_program.prompt.instruction}"
```

### AutoMode Configuration

MIPROv2 provides preset configurations for different optimization scenarios:

```ruby
# Light optimization - fastest, good for prototyping
# 6 trials, 3 instruction candidates, greedy strategy
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.light(metric: metric)

# Medium optimization - balanced performance and speed
# 12 trials, 5 instruction candidates, adaptive strategy
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium(metric: metric)

# Heavy optimization - most thorough, best results
# 18 trials, 8 instruction candidates, Bayesian optimization
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.heavy(metric: metric)

# Run optimization with any mode
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)
```

### Custom Configuration

```ruby
# Class-level configuration (affects all instances)
DSPy::Teleprompt::MIPROv2.configure do |config|
  config.optimization_strategy = :bayesian      # :greedy, :adaptive, or :bayesian
  config.num_trials = 15                        # Total optimization trials
  config.num_instruction_candidates = 8         # Instruction variants to generate
  config.bootstrap_sets = 6                     # Bootstrap example sets to create
  config.max_bootstrapped_examples = 4          # Max examples per bootstrap set
  config.max_labeled_examples = 16              # Max labeled examples to use
  config.init_temperature = 1.2                 # Initial exploration temperature
  config.final_temperature = 0.05               # Final exploitation temperature
  config.early_stopping_patience = 4            # Trials without improvement before stopping
  config.use_bayesian_optimization = true       # Enable Gaussian Process optimization
  config.track_diversity = true                 # Track candidate diversity metrics
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)

# Or instance-level configuration (overrides class defaults)
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
optimizer.configure do |config|
  config.optimization_strategy = :adaptive
  config.num_trials = 20
  config.bootstrap_sets = 8
end
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)
```

## Configuration Options

### Configuration Parameters

MIPROv2 uses `dry-configurable` for settings management. You can configure at both class and instance levels:

```ruby
# Class-level configuration (affects all new instances)
DSPy::Teleprompt::MIPROv2.configure do |config|
  # Core optimization settings
  config.num_trials = 12                          # Total optimization trials to run
  config.num_instruction_candidates = 5           # Number of instruction variants to generate
  config.bootstrap_sets = 5                       # Number of bootstrap example sets
  config.max_bootstrapped_examples = 4            # Max examples per bootstrap set
  config.max_labeled_examples = 16                # Max labeled examples from trainset

  # Optimization strategy (:greedy, :adaptive, or :bayesian)
  config.optimization_strategy = :adaptive
  config.use_bayesian_optimization = true         # Enable Gaussian Process optimization

  # Temperature scheduling for exploration/exploitation balance
  config.init_temperature = 1.0                   # Initial exploration temperature
  config.final_temperature = 0.1                  # Final exploitation temperature

  # Early stopping
  config.early_stopping_patience = 3              # Stop after N trials without improvement

  # Additional tracking
  config.track_diversity = true                    # Track candidate diversity metrics
end

# Instance-level configuration (overrides class defaults)
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: your_metric)
optimizer.configure do |config|
  config.num_trials = 20
  config.optimization_strategy = :bayesian
end
```

### AutoMode Configurations

```ruby
# Light mode values:
# - num_trials: 6
# - num_instruction_candidates: 3
# - max_bootstrapped_examples: 2
# - max_labeled_examples: 8
# - bootstrap_sets: 3
# - optimization_strategy: :greedy
# - early_stopping_patience: 2

# Medium mode values (balanced default):
# - num_trials: 12
# - num_instruction_candidates: 5
# - max_bootstrapped_examples: 4
# - max_labeled_examples: 16
# - bootstrap_sets: 5
# - optimization_strategy: :adaptive
# - early_stopping_patience: 3

# Heavy mode values (best results):
# - num_trials: 18
# - num_instruction_candidates: 8
# - max_bootstrapped_examples: 6
# - max_labeled_examples: 24
# - bootstrap_sets: 8
# - optimization_strategy: :bayesian  # Uses Gaussian Processes
# - early_stopping_patience: 5
```

## Optimization Phases

### Phase 1: Bootstrap Few-Shot Examples

Generate diverse, high-quality few-shot examples using multiple bootstrap strategies:

## Optimizing Composite Programs (ReAct, CodeAct, Chains)

MIPROv2 can optimize any DSPy program that exposes predictors, including composite agents such as `DSPy::ReAct`, `DSPy::CodeAct`, and custom chains. Ruby now mirrors Python’s predictor discovery:

- Each composite module reports its internal `DSPy::Predict` components (e.g., ReAct’s thought and observation predictors).
- `create_n_fewshot_demo_sets` allocates few-shot buckets per predictor, so multi-module programs receive balanced bootstrap coverage.
- The optimization trace (`result.optimization_trace[:trial_logs]`) records per-predictor instructions and demo sets for observability parity.

### Minimal ReAct Example

```ruby
class QA < DSPy::Signature
  description "Answer short factual questions"

  input  { const :question, String }
  output { const :answer,   String }
end

tools = [MyLookupTool.new] # implements DSPy::Tools::Base
program = DSPy::ReAct.new(QA, tools:, max_iterations: 1)

metric = proc do |example, prediction|
  prediction.answer&.downcase&.include?(example.expected[:answer].downcase)
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
optimizer.configure do |config|
  config.num_trials = 1                 # keep token usage low
  config.num_instruction_candidates = 1
  config.bootstrap_sets = 1
end

result = optimizer.compile(
  program,
  trainset: training_examples,
  valset:   validation_examples
)

best_program = result.optimized_program
trial_logs   = result.optimization_trace[:trial_logs]
```

The integration spec `spec/integration/dspy/mipro_v2_re_act_integration_spec.rb` (recorded with VCR) showcases this flow end-to-end against OpenAI’s `gpt-4o-mini`, confirming per-predictor awareness with real LLM traces. Use the same pattern for CodeAct or chained predictors—MIPROv2 will enumerate each module, assign demos, and tune instructions automatically.

```ruby
# MIPROv2 automatically creates multiple candidate sets of few-shot examples
# Each set contains examples with reasoning traces generated using CoT
# Bootstrap creates several independent sets for diversity

# You can observe bootstrap progress through events:
DSPy.events.subscribe('phase_start') do |event_name, attributes|
  if attributes[:phase] == 1 && attributes[:name] == 'bootstrap'
    puts "Starting bootstrap phase..."
  end
end

DSPy.events.subscribe('phase_complete') do |event_name, attributes|
  if attributes[:phase] == 1
    puts "Bootstrap complete. Success rate: #{attributes[:success_rate]}"
    puts "Created #{attributes[:candidate_sets]} bootstrap sets"
  end
end
```

### Phase 2: Instruction Proposal

Generate multiple high-quality instruction candidates using the grounded proposer:

```ruby
# The grounded proposer analyzes your task and generates contextual instructions:
# - "Analyze the sentiment of the given text step by step, providing detailed reasoning"
# - "Classify the emotional tone by examining key indicators in the text"
# - "Determine sentiment by evaluating positive and negative language patterns"

# Monitor instruction generation:
DSPy.events.subscribe('phase_complete') do |event_name, attributes|
  if attributes[:phase] == 2
    puts "Generated #{attributes[:num_candidates]} instruction candidates"
    puts "Best instruction preview: #{attributes[:best_instruction_preview]}"
  end
end
```

### Phase 3: Bayesian Optimization

Intelligently explore candidate configurations using advanced optimization strategies:

```ruby
# Creates candidate configurations combining instructions + few-shot examples:
# - Baseline (no modifications)
# - Instruction-only candidates
# - Few-shot-only candidates  
# - Combined candidates (instruction + few-shot examples)

# Uses optimization strategies:
# - Greedy: Exploit best known configurations
# - Adaptive: Balance exploration/exploitation with temperature scheduling
# - Bayesian: Use Gaussian Processes for intelligent candidate selection

# Monitor optimization progress:
DSPy.events.subscribe('trial_start') do |event_name, attributes|
  puts "Trial #{attributes[:trial_number]}: Testing #{attributes[:candidate_id]}"
  puts "Instruction: #{attributes[:instruction_preview]}"
end

DSPy.events.subscribe('trial_complete') do |event_name, attributes|
  if attributes[:is_best]
    puts "New best score: #{attributes[:score]} (Trial #{attributes[:trial_number]})"
  end
end
```

## Working with Results

### MIPROv2Result Object

```ruby
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)

# Access optimization results
puts "Best score: #{result.best_score_value}"
puts "Score name: #{result.best_score_name}"
puts "Total trials: #{result.history[:total_trials]}"
puts "Early stopped: #{result.history[:early_stopped]}"

# Get the optimized program
optimized_program = result.optimized_program

# Access MIPROv2-specific results
puts "Evaluated candidates: #{result.evaluated_candidates.size}"
puts "Bootstrap success rate: #{result.bootstrap_statistics[:success_rate]}"
puts "Proposal themes: #{result.proposal_statistics[:common_themes]}"

# Access optimization trace
if result.optimization_trace[:score_history]
  puts "Score progression: #{result.optimization_trace[:score_history]}"
end

# Access detailed evaluation results for best candidate
if result.best_evaluation_result
  eval_result = result.best_evaluation_result
  puts "Total examples evaluated: #{eval_result.total_examples}"
  puts "Pass rate: #{eval_result.pass_rate}"
  puts "Individual results: #{eval_result.results.size}"
end
```

### Best Configuration Access

```ruby
# Access best candidate configuration
best_candidates = result.evaluated_candidates.select { |c| c.type == DSPy::Teleprompt::CandidateType::Combined }
best_candidate = best_candidates.first

if best_candidate
  puts "Best instruction: #{best_candidate.instruction}"
  puts "Number of few-shot examples: #{best_candidate.few_shot_examples.size}"
  puts "Candidate type: #{best_candidate.type.serialize}"
  puts "Configuration ID: #{best_candidate.config_id}"
  puts "Metadata: #{best_candidate.metadata}"

  # Inspect few-shot examples
  best_candidate.few_shot_examples.each_with_index do |example, i|
    puts "Example #{i+1}:"
    puts "  Input: #{example.input_values}"
    puts "  Output: #{example.expected_values}"
  end
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
# Define custom metric with detailed evaluation
custom_metric = proc do |example, prediction|
  # Return hash with detailed metrics (recommended)
  {
    passed: prediction.sentiment.downcase == example.expected_sentiment.downcase,
    confidence_score: prediction.confidence || 0.0,
    answer_quality: prediction.sentiment ? 1.0 : 0.0,
    reasoning_present: !prediction.reasoning.nil?
  }
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: custom_metric)
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)

# Access detailed metrics in results
if result.best_evaluation_result
  result.best_evaluation_result.results.each do |eval_result|
    metrics = eval_result.metrics
    puts "Confidence: #{metrics[:confidence_score]}"
    puts "Has reasoning: #{metrics[:reasoning_present]}"
  end
end
```

### Validation Split

```ruby
# Use separate validation set for unbiased evaluation
# MIPROv2 automatically uses valset if provided, otherwise splits trainset
result = optimizer.compile(
  program,
  trainset: training_examples,
  valset: validation_examples  # Optional: uses 1/3 of trainset if not provided
)

# Force using part of training set for validation
result = optimizer.compile(
  program,
  trainset: training_examples
  # valset: nil - will automatically use trainset.take(trainset.size / 3)
)
```

### Monitoring Progress

```ruby
# Subscribe to optimization events for detailed progress tracking
DSPy.events.subscribe('miprov2_compile') do |event_name, attributes|
  puts "Starting MIPROv2 optimization with #{attributes[:num_trials]} trials"
  puts "Strategy: #{attributes[:optimization_strategy]}"
  puts "Mode: #{attributes[:mode]}"
end

DSPy.events.subscribe('phase_start') do |event_name, attributes|
  phase_names = { 1 => 'Bootstrap', 2 => 'Instruction Proposal', 3 => 'Optimization' }
  puts "Phase #{attributes[:phase]}: #{phase_names[attributes[:phase]]} starting..."
end

DSPy.events.subscribe('phase_complete') do |event_name, attributes|
  case attributes[:phase]
  when 1
    puts "Bootstrap complete: #{attributes[:success_rate]} success rate"
  when 2  
    puts "Generated #{attributes[:num_candidates]} instruction candidates"
  when 3
    puts "Optimization complete: Best score #{attributes[:best_score]}"
  end
end

DSPy.events.subscribe('trial_complete') do |event_name, attributes|
  status = attributes[:is_best] ? " (NEW BEST!)" : ""
  puts "Trial #{attributes[:trial_number]}: #{attributes[:score]}#{status}"
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: custom_metric)
result = optimizer.compile(program, trainset: training_examples)
```

## Best Practices

### 1. Choose Appropriate Mode

```ruby
# For quick experimentation (6 trials, greedy strategy)
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.light(metric: your_metric)

# For production optimization (18 trials, Bayesian optimization)
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.heavy(metric: your_metric)

# For balanced optimization (12 trials, adaptive strategy)
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium(metric: your_metric)

# All modes support the same compile interface
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)
```

### 2. Provide Quality Examples

```ruby
# Use diverse, high-quality training examples
training_examples = [
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "I love this product! It's amazing." },
    expected: { sentiment: "positive", confidence: 0.9 }
  ),
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "This is the worst experience I've ever had." },
    expected: { sentiment: "negative", confidence: 0.95 }
  ),
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "The product is okay, nothing special." },
    expected: { sentiment: "neutral", confidence: 0.7 }
  )
  # ... more diverse examples
]
```

### 3. Robust Evaluation

```ruby
# Robust metric that handles errors gracefully
robust_metric = proc do |example, prediction|
  begin
    # Handle missing predictions
    return { passed: false, error: "no_prediction" } unless prediction
    
    # Handle missing sentiment
    return { passed: false, error: "missing_sentiment" } unless prediction.sentiment
    
    # Successful evaluation
    passed = prediction.sentiment.downcase == example.expected_sentiment.downcase
    confidence = prediction.respond_to?(:confidence) ? prediction.confidence : 0.0
    
    {
      passed: passed,
      confidence_score: confidence,
      sentiment_match: passed,
      prediction_length: prediction.sentiment.length
    }
  rescue => e
    # Handle any unexpected errors
    DSPy.logger.warn("Evaluation error: #{e.message}")
    { passed: false, error: e.message }
  end
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: robust_metric)
result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)
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
      minimum_score: 0.8,
      optimizer: 'MIPROv2',
      strategy: result.history[:optimization_strategy],
      total_trials: result.history[:total_trials]
    }
  )
end
```

## Advanced Features

### Bayesian Optimization with Gaussian Processes

MIPROv2 includes state-of-the-art Bayesian optimization using Gaussian Processes for intelligent candidate selection:

```ruby
# Enable Bayesian optimization (default in heavy mode)
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: your_metric)
optimizer.configure do |config|
  config.optimization_strategy = :bayesian
  config.use_bayesian_optimization = true
end

result = optimizer.compile(program, trainset: training_examples, valset: validation_examples)

# Bayesian optimization provides:
# - Intelligent exploration vs exploitation balance
# - Upper Confidence Bound (UCB) acquisition function
# - Gaussian Process modeling of candidate performance
# - Adaptive exploration parameter based on trial progress
```

### Optimization Strategies Comparison

```ruby
# Greedy Strategy - Fastest
# - Prioritizes unexplored candidates first
# - Then selects highest scoring candidates
# - Best for: Quick experiments, limited compute budget
config.optimization_strategy = :greedy

# Adaptive Strategy - Balanced  
# - Temperature-based exploration/exploitation balance
# - Probabilistic candidate selection with softmax
# - Progressive cooling from exploration to exploitation
# - Best for: General-purpose optimization
config.optimization_strategy = :adaptive

# Bayesian Strategy - Most Sophisticated
# - Gaussian Process modeling of candidate performance
# - Upper Confidence Bound acquisition function
# - Intelligent uncertainty-aware selection
# - Best for: High-stakes optimization, maximum performance
config.optimization_strategy = :bayesian
```

### Strategy Trade-offs

Choosing the right strategy depends on your trial budget and how deterministic your metric is:

- **Greedy (`:greedy`)** — lowest token spend. Explore each candidate once, then exploit the best so far. Ideal for smoke tests, daily regressions, or when you only have ~3–5 trials. Won’t recover well from noisy metrics because it never revisits candidates.
- **Adaptive (`:adaptive`)** — balanced default. Uses temperature-based softmax sampling so it continues to explore while scores are noisy, then converges. Use this when you have 6–15 trials and want a “set it and forget it” policy.
- **Bayesian (`:bayesian`)** — highest quality, highest compute. Trains a Gaussian Process after every update, which adds \(O(n^3)\) modeling cost and makes runs inherently sequential. Only pays off when you have ≥10 trials, reasonably smooth metrics, and care about squeezing out the last few percentage points. Expect 1–2 s extra Ruby time per trial for GP fitting.

Tip: start with `:adaptive`, switch to `:greedy` for quick CI checks, and reserve `:bayesian` for longer runs (nightly, staging) once you’ve confirmed the metric is stable.

### Candidate Configuration Types

MIPROv2 generates and evaluates four types of candidate configurations:

```ruby
# Access evaluated candidates to understand what was tested
result.evaluated_candidates.each do |candidate|
  case candidate.type
  when DSPy::Teleprompt::CandidateType::Baseline
    puts "Baseline: No modifications to original program"
  when DSPy::Teleprompt::CandidateType::InstructionOnly
    puts "Instruction-only: #{candidate.instruction[0,50]}..."
  when DSPy::Teleprompt::CandidateType::FewShotOnly
    puts "Few-shot-only: #{candidate.few_shot_examples.size} examples"
  when DSPy::Teleprompt::CandidateType::Combined
    puts "Combined: Instruction + #{candidate.few_shot_examples.size} examples"
    puts "  Instruction: #{candidate.instruction[0,50]}..."
  end
  
  puts "  Config ID: #{candidate.config_id}"
  puts "  Metadata: #{candidate.metadata}"
end
```

### Working with EvaluatedCandidate Data

The `EvaluatedCandidate` is an immutable `Data` class that represents a tested configuration:

```ruby
# EvaluatedCandidate contains:
# - instruction: String - the instruction used
# - few_shot_examples: Array - the few-shot examples used
# - type: CandidateType - the type of candidate (baseline, instruction_only, etc.)
# - metadata: Hash - additional metadata about the candidate
# - config_id: String - unique identifier for this configuration

result.evaluated_candidates.each do |candidate|
  puts "Config ID: #{candidate.config_id}"
  puts "Type: #{candidate.type.serialize}"
  puts "Instruction: #{candidate.instruction}"
  puts "Examples count: #{candidate.few_shot_examples.size}"
  puts "Metadata: #{candidate.metadata}"
  puts "---"
end
```
