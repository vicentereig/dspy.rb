---
layout: docs
title: "GEPA Optimizer: Genetic Algorithm Prompt Optimization for Ruby LLMs"
name: GEPA Optimizer
description: "Achieve 3x better LLM performance with GEPA's multi-objective optimization. Pareto-optimal prompts, automatic tuning, Ruby code examples included."
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: GEPA Optimizer
  url: "/optimization/gepa/"
prev:
- name: MIPROv2
  url: "/optimization/miprov2/"
next:
- name: Benchmarking Raw Prompts
  url: "/optimization/benchmarking-raw-prompts/"
---

# GEPA (Genetic-Pareto)

GEPA (Genetic-Pareto) is an advanced prompt optimizer that uses genetic algorithms for multi-objective optimization of DSPy programs. It combines evolutionary computation with Pareto-optimal solution selection to find the best trade-offs between different optimization objectives.

## Quick Start

```ruby
require 'dspy'

# Configure your LM
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
end

# Create a signature
class QASignature < DSPy::Signature
  description "Answer questions accurately"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

# Create a program to optimize
program = DSPy::Predict.new(QASignature)

# Create training examples
trainset = [
  DSPy::Example.new(
    signature_class: QASignature,
    input: { question: "What is 2+2?" },
    expected: { answer: "4" }
  ),
  DSPy::Example.new(
    signature_class: QASignature,
    input: { question: "What is the capital of France?" },
    expected: { answer: "Paris" }
  )
]

# Define a metric with feedback
class ExactMatchMetric
  include DSPy::Teleprompt::GEPAFeedbackMetric
  
  def call(example, prediction, trace = nil)
    expected = example.expected_values[:answer].downcase.strip
    actual = prediction.answer.downcase.strip
    
    if expected == actual
      DSPy::Teleprompt::ScoreWithFeedback.new(
        score: 1.0,
        prediction: prediction,
        feedback: "Correct answer"
      )
    else
      DSPy::Teleprompt::ScoreWithFeedback.new(
        score: 0.0,
        prediction: prediction,
        feedback: "Expected '#{expected}', got '#{actual}'. Check accuracy."
      )
    end
  end
end

# Configure reflection LM (required)
config = DSPy::Teleprompt::GEPA::GEPAConfig.new
config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

# Optimize with GEPA (Genetic-Pareto)
gepa = DSPy::Teleprompt::GEPA.new(metric: ExactMatchMetric.new, config: config)
optimized_program = gepa.compile(program, trainset: trainset)

# Use the optimized program
result = optimized_program.call(question: "What is 3+3?")
puts result.answer
```

## Configuration

### Basic Configuration

```ruby
config = DSPy::Teleprompt::GEPA::GEPAConfig.new
config.population_size = 8      # Number of program variants (default: 8)
config.num_generations = 10     # Optimization rounds (default: 10)
config.mutation_rate = 0.7      # Probability of mutation (default: 0.7)
config.crossover_rate = 0.6     # Probability of crossover (default: 0.6)
config.use_pareto_selection = true  # Use Pareto frontier selection (default: true)
config.simple_mode = false      # Use simple optimization without full genetic algorithm (default: false)
config.reflection_lm = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])  # LM for reflection (required)

gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
```

### Light Configuration (Fast)

```ruby
config = DSPy::Teleprompt::GEPA::GEPAConfig.new
config.population_size = 4
config.num_generations = 2
config.mutation_rate = 0.8
config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
```

### Heavy Configuration (Thorough)

```ruby
config = DSPy::Teleprompt::GEPA::GEPAConfig.new
config.population_size = 12
config.num_generations = 15
config.mutation_rate = 0.6
config.crossover_rate = 0.8
config.reflection_lm = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])

gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
```

### All Configuration Options

```ruby
config = DSPy::Teleprompt::GEPA::GEPAConfig.new

# Core genetic algorithm settings
config.population_size = 8          # Number of program variants in each generation
config.num_generations = 10         # Number of evolution iterations
config.mutation_rate = 0.7          # Probability of mutation (0.0-1.0)
config.crossover_rate = 0.6         # Probability of crossover (0.0-1.0)

# Algorithm behavior
config.use_pareto_selection = true  # Use Pareto frontier for multi-objective optimization
config.simple_mode = false          # If true, uses simplified optimization without full GA

# LM for reflection (required - no default)
config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

# Advanced: Mutation types (default: all types)
config.mutation_types = [
  DSPy::Teleprompt::GEPA::MutationType::Rewrite,   # Complete rewording
  DSPy::Teleprompt::GEPA::MutationType::Expand,    # Add detail/context
  DSPy::Teleprompt::GEPA::MutationType::Simplify,  # Remove complexity
  DSPy::Teleprompt::GEPA::MutationType::Combine,   # Merge with another
  DSPy::Teleprompt::GEPA::MutationType::Rephrase   # Minor rewording
]

# Advanced: Crossover types (default: all types)
config.crossover_types = [
  DSPy::Teleprompt::GEPA::CrossoverType::Uniform,    # Random selection
  DSPy::Teleprompt::GEPA::CrossoverType::Blend,      # Weighted combination
  DSPy::Teleprompt::GEPA::CrossoverType::Structured  # Structure-aware
]
```

## Writing Metrics

GEPA can work with two types of metrics:

### Option 1: Simple Proc Metric (Easiest)

For basic use cases, you can use a simple proc that returns a float score:

```ruby
# Simple accuracy metric
metric = proc do |example, prediction|
  expected = example.expected_values[:answer]
  actual = prediction.answer
  expected == actual ? 1.0 : 0.0
end

# Use with GEPA
gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
```

Note: When using a simple proc, GEPA will still perform optimization but without detailed feedback for reflection.

### Option 2: Feedback Metric with GEPAFeedbackMetric (Advanced)

```ruby
class FeedbackMetric
  include DSPy::Teleprompt::GEPAFeedbackMetric
  
  def call(example, prediction, trace = nil)
    expected = example.expected_values[:answer]
    actual = prediction.answer
    
    score = calculate_score(expected, actual)
    feedback = generate_feedback(expected, actual, score)
    
    DSPy::Teleprompt::ScoreWithFeedback.new(
      score: score,
      prediction: prediction,
      feedback: feedback
    )
  end
  
  private
  
  def calculate_score(expected, actual)
    # Your scoring logic
    expected.downcase == actual.downcase ? 1.0 : 0.0
  end
  
  def generate_feedback(expected, actual, score)
    if score > 0.8
      "Good answer"
    elsif score > 0.5
      "Partially correct, but could be more precise"
    else
      "Expected '#{expected}', got '#{actual}'. Review the question carefully."
    end
  end
end
```

## Comparing Optimizers

```ruby
# Test baseline
baseline_score = evaluate_program(program, testset, simple_metric)

# Optimize with MIPROv2
mipro = DSPy::Teleprompt::MIPROv2.new(metric: simple_metric)
mipro_optimized = mipro.compile(program, trainset: trainset)
mipro_score = evaluate_program(mipro_optimized, testset, simple_metric)

# Optimize with GEPA (Genetic-Pareto)
gepa = DSPy::Teleprompt::GEPA.new(metric: feedback_metric)
gepa_optimized = gepa.compile(program, trainset: trainset)
gepa_score = evaluate_program(gepa_optimized, testset, simple_metric)

puts "Baseline: #{baseline_score}"
puts "MIPROv2:  #{mipro_score}"
puts "GEPA (Genetic-Pareto): #{gepa_score}"
```

## When to Use GEPA (Genetic-Pareto)

### Use GEPA (Genetic-Pareto) when:
- You want detailed feedback on why examples fail
- Your task benefits from iterative prompt refinement
- You have complex evaluation criteria
- You need to understand optimization decisions

### Use MIPROv2 when:
- You have simple success/failure metrics
- You want faster optimization
- Your prompts are already close to optimal
- You prefer less configuration

## Common Patterns

### Math Problems

```ruby
class MathSignature < DSPy::Signature
  description "Solve math problems step by step"
  
  input do
    const :problem, String
  end
  
  output do
    const :answer, String
    const :reasoning, String
  end
end

class MathMetric
  include DSPy::Teleprompt::GEPAFeedbackMetric
  
  def call(example, prediction, trace = nil)
    expected_num = extract_number(example.expected_values[:answer])
    actual_num = extract_number(prediction.answer)
    
    if expected_num && actual_num && expected_num == actual_num
      DSPy::Teleprompt::ScoreWithFeedback.new(
        score: 1.0,
        prediction: prediction,
        feedback: "Correct calculation"
      )
    else
      DSPy::Teleprompt::ScoreWithFeedback.new(
        score: 0.0,
        prediction: prediction,
        feedback: "Check your arithmetic. Show step-by-step work."
      )
    end
  end
  
  private
  
  def extract_number(text)
    text.scan(/\d+/).first&.to_i
  end
end
```

### Text Classification

```ruby
class ClassificationMetric
  include DSPy::Teleprompt::GEPAFeedbackMetric
  
  def call(example, prediction, trace = nil)
    expected = example.expected_values[:category].downcase
    actual = prediction.category.downcase
    
    score = expected == actual ? 1.0 : 0.0
    
    feedback = if score > 0
      "Correct classification"
    else
      "Misclassified as '#{actual}', should be '#{expected}'. Consider the key indicators in the text."
    end
    
    DSPy::Teleprompt::ScoreWithFeedback.new(
      score: score,
      prediction: prediction,
      feedback: feedback
    )
  end
end
```

## Troubleshooting

### GEPA (Genetic-Pareto) Takes Too Long
- Reduce `population_size` and `num_generations`
- Use a faster model: `config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])`
- Enable simple mode: `config.simple_mode = true`
- Use fewer training examples

### Poor Optimization Results
- Check your metric implementation
- Ensure training examples are representative
- Add more diverse training examples
- Increase `num_generations`

### Feedback Not Helpful
- Make feedback more specific in your metric
- Include examples of good vs bad answers
- Reference the input context in feedback

### API Errors
- Check your API key configuration
- Verify LM model names
- Handle rate limiting in your metric

## Examples

See the `examples/` directory for complete working examples:

- `minimal_gepa_test.rb` - Basic GEPA (Genetic-Pareto) usage
- `simple_gepa_benchmark.rb` - GEPA (Genetic-Pareto) vs MIPROv2 comparison
- `gepa_benchmark.rb` - Comprehensive benchmarking

These examples show real usage patterns and can be run with your API keys.

## Related Topics

### Other Optimization Methods
- **[MIPROv2](/optimization/miprov2/)** - Alternative optimization algorithm for comparison with GEPA
- **[Simple Optimizer](/optimization/simple-optimizer/)** - Quick random search optimization for getting started
- **[Prompt Optimization](/optimization/prompt-optimization/)** - General principles of programmatic prompt improvement

### Evaluation & Metrics
- **[Evaluation](/optimization/evaluation/)** - Systematically test and measure your optimized programs
- **[Custom Metrics](/advanced/custom-metrics/)** - Build domain-specific evaluation metrics for GEPA optimization
- **[Benchmarking](/optimization/benchmarking-raw-prompts/)** - Compare optimized vs unoptimized approaches

### Advanced Applications
- **[RAG Optimization](/advanced/rag/)** - Use GEPA to optimize retrieval-augmented generation systems  
- **[Complex Types](/advanced/complex-types/)** - Optimize programs working with structured data
- **[Multi-stage Pipelines](/advanced/pipelines/)** - Optimize complex processing workflows

### Framework Comparison
- **[DSPy.rb vs LangChain](/advanced/dspy-vs-langchain/)** - Compare optimization capabilities across Ruby frameworks

### Production
- **[Storage](/production/storage/)** - Persist and manage your optimized GEPA programs
- **[Registry](/production/registry/)** - Version management for GEPA-optimized configurations