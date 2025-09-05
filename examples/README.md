# GEPA Examples

This directory contains practical examples of using GEPA (Genetic-Pareto Reflective Prompt Evolution) with DSPy.rb.

## Prerequisites

Set your OpenAI API key:
```bash
export OPENAI_API_KEY="your-api-key-here"
```

## Examples

### `minimal_gepa_test.rb` - Basic GEPA Test

A minimal example that mirrors the Python DSPy GEPA usage pattern:

```bash
ruby examples/minimal_gepa_test.rb
```

**What it does:**
- Creates a simple Q&A program
- Optimizes it with GEPA using one training example
- Shows before/after results

**Good for:** Understanding basic GEPA workflow

### `simple_gepa_benchmark.rb` - GEPA vs MIPROv2

Direct Ruby equivalent of the Python GEPA example from the DSPy documentation:

```bash
ruby examples/simple_gepa_benchmark.rb
```

**What it does:**
- Compares GEPA vs MIPROv2 on simple math questions
- Shows accuracy and timing for both optimizers
- Uses the same structure as Python DSPy examples

**Good for:** Comparing optimizer performance

### `gepa_benchmark.rb` - Comprehensive Benchmark

A more thorough benchmark with multiple test cases:

```bash
ruby examples/gepa_benchmark.rb
```

**What it does:**
- Tests on math word problems
- Uses multiple training and validation examples
- Provides detailed performance analysis
- Shows optimized instructions

**Good for:** Production evaluation scenarios

## Key Differences from Python DSPy

| Python DSPy | Ruby DSPy.rb |
|------------|--------------|
| `d.Predict('q -> a')` | `DSPy::Predict.new(QASignature)` |
| `auto='light'` | Manual config setup |
| 5-arg metric | 3-arg metric with ScoreWithFeedback |
| `d.GEPA(metric=..., reflection_lm=...)` | `DSPy::Teleprompt::GEPA.new(metric:, config:)` |

## Example Output

```
🚀 Simple GEPA Benchmark (Ruby version of Python example)
============================================================

📊 Dataset:
  Training examples: 1
  Validation examples: 3

🔍 Testing baseline program:
  Input: '2+2?'
  Baseline output: '4'
  Expected: '4'

  Baseline validation accuracy: 66.7%

⚡ Optimizing with MIPROv2...
  MIPROv2 output: '4'
  Optimization time: 2.34s
  MIPROv2 validation accuracy: 100.0%

🧬 Optimizing with GEPA...
  GEPA output: '4'
  Optimization time: 5.67s
  GEPA validation accuracy: 100.0%

📈 Final Results:
========================================
  Method       Accuracy    Time (s)
----------------------------------------
  Baseline       66.7%           -
  MIPROv2       100.0%        2.34
  GEPA          100.0%        5.67

🤝 It's a tie!

✅ Simple GEPA benchmark completed!
```

## Creating Your Own Examples

1. **Start with a signature:**
```ruby
class MySignature < DSPy::Signature
  description "Your task description"
  
  input do
    const :input_field, String
  end
  
  output do
    const :output_field, String
  end
end
```

2. **Create training examples:**
```ruby
trainset = [
  DSPy::Example.new(MySignature,
    input: { input_field: "example input" },
    expected: { output_field: "expected output" }
  )
]
```

3. **Define a metric with feedback:**
```ruby
class MyMetric
  include DSPy::Teleprompt::GEPAFeedbackMetric
  
  def call(example, prediction, trace = nil)
    # Your evaluation logic
    score = calculate_score(example, prediction)
    feedback = generate_feedback(example, prediction, score)
    
    DSPy::Teleprompt::ScoreWithFeedback.new(
      score: score,
      prediction: prediction,
      feedback: feedback
    )
  end
end
```

4. **Run optimization:**
```ruby
gepa = DSPy::Teleprompt::GEPA.new(metric: MyMetric.new)
optimized = gepa.compile(program, trainset: trainset)
```

## Tips

- Start with `minimal_gepa_test.rb` to understand the basics
- Use smaller configurations for testing (`population_size: 2, num_generations: 1`)
- Check your metric logic with simple examples first
- GEPA works best with specific, actionable feedback in your metric