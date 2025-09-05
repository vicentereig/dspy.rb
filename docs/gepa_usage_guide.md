# GEPA Usage Guide

GEPA (Genetic-Pareto Reflective Prompt Evolution) is a prompt optimizer that uses genetic algorithms and LLM reflection to improve DSPy programs.

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
  DSPy::Example.new(QASignature,
    input: { question: "What is 2+2?" },
    expected: { answer: "4" }
  ),
  DSPy::Example.new(QASignature,
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

# Optimize with GEPA
gepa = DSPy::Teleprompt::GEPA.new(metric: ExactMatchMetric.new)
optimized_program = gepa.compile(program, trainset: trainset)

# Use the optimized program
result = optimized_program.call(question: "What is 3+3?")
puts result.answer
```

## Configuration

### Basic Configuration

```ruby
config = DSPy::Teleprompt::GEPA::GEPAConfig.new
config.population_size = 8      # Number of program variants
config.num_generations = 5      # Optimization rounds  
config.mutation_rate = 0.7      # Probability of mutation
config.crossover_rate = 0.6     # Probability of crossover
config.reflection_lm = "openai/gpt-4o"  # LM for reflection

gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
```

### Light Configuration (Fast)

```ruby
config = DSPy::Teleprompt::GEPA::GEPAConfig.new
config.population_size = 4
config.num_generations = 2
config.mutation_rate = 0.8
config.reflection_lm = "openai/gpt-4o-mini"

gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
```

### Heavy Configuration (Thorough)

```ruby
config = DSPy::Teleprompt::GEPA::GEPAConfig.new
config.population_size = 12
config.num_generations = 10
config.mutation_rate = 0.6
config.crossover_rate = 0.8
config.reflection_lm = "openai/gpt-4o"

gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
```

## Writing Metrics

### Simple Metric (for MIPROv2)

```ruby
simple_metric = proc do |example, prediction|
  expected = example.expected_values[:answer]
  actual = prediction.answer
  expected == actual ? 1.0 : 0.0
end
```

### Feedback Metric (for GEPA)

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

# Optimize with GEPA
gepa = DSPy::Teleprompt::GEPA.new(metric: feedback_metric)
gepa_optimized = gepa.compile(program, trainset: trainset)
gepa_score = evaluate_program(gepa_optimized, testset, simple_metric)

puts "Baseline: #{baseline_score}"
puts "MIPROv2:  #{mipro_score}"
puts "GEPA:     #{gepa_score}"
```

## When to Use GEPA

### Use GEPA when:
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

### GEPA Takes Too Long
- Reduce `population_size` and `num_generations`
- Use `config.reflection_lm = "openai/gpt-4o-mini"`
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

- `minimal_gepa_test.rb` - Basic GEPA usage
- `simple_gepa_benchmark.rb` - GEPA vs MIPROv2 comparison
- `gepa_benchmark.rb` - Comprehensive benchmarking

These examples show real usage patterns and can be run with your API keys.