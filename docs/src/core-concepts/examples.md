---
layout: docs
name: Examples
description: Type-safe training and evaluation data objects
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Examples
  url: "/core-concepts/examples/"
nav:
  prev:
    name: Predictors
    url: "/core-concepts/predictors/"
  next:
    name: Optimization
    url: "/optimization/"
date: 2025-07-10 00:00:00 +0000
---
# Examples

Examples are type-safe training and evaluation data objects. DSPy.rb provides two types of examples: basic examples for evaluation and few-shot examples for prompt enhancement.

## Creating Basic Examples

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

# Create examples with known correct outputs
examples = [
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "I absolutely love this product!" },
    expected: { 
      sentiment: ClassifyText::Sentiment::Positive, 
      confidence: 0.95 
    }
  ),
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "This is the worst experience ever." },
    expected: { 
      sentiment: ClassifyText::Sentiment::Negative, 
      confidence: 0.92 
    }
  ),
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "The weather is okay today." },
    expected: { 
      sentiment: ClassifyText::Sentiment::Neutral, 
      confidence: 0.78 
    }
  )
]
```

## Type Safety and Validation

Examples are automatically validated against your signature's type constraints:

```ruby
# This will raise a validation error
invalid_example = DSPy::Example.new(
  signature_class: ClassifyText,
  input: { text: "Sample text" },
  expected: { 
    sentiment: "positive",  # String instead of Sentiment enum - ERROR!
    confidence: 1.5
  }
)
# => ArgumentError: Type error in expected output for ClassifyText: ...
```

## Working with Examples

### Accessing Example Data

```ruby
example = DSPy::Example.new(
  signature_class: ClassifyText,
  input: { text: "Great product!" },
  expected: { sentiment: ClassifyText::Sentiment::Positive, confidence: 0.9 }
)

# Access input values
input_values = example.input_values
# => { text: "Great product!" }

# Access expected output values
expected_values = example.expected_values  
# => { sentiment: #<Sentiment::Positive>, confidence: 0.9 }

# Convert to hash for serialization
example.to_h
# => { signature_class: "ClassifyText", input: {...}, expected: {...} }
```

### Evaluating Predictions

```ruby
# Test if a prediction matches the expected output
predictor = DSPy::Predict.new(ClassifyText)
result = predictor.call(text: "Great product!")

# Check if prediction matches expected
if example.matches_prediction?(result)
  puts "Prediction matches expected output!"
else
  puts "Prediction differs from expected output"
end
```

### Batch Validation

```ruby
# Validate multiple examples at once
examples_data = [
  {
    input: { text: "Great product!" },
    expected: { sentiment: ClassifyText::Sentiment::Positive, confidence: 0.9 }
  },
  {
    input: { text: "Terrible service." },
    expected: { sentiment: ClassifyText::Sentiment::Negative, confidence: 0.8 }
  }
]

validated_examples = DSPy::Example.validate_batch(ClassifyText, examples_data)
# Returns array of validated DSPy::Example objects
```

## Few-Shot Examples

Few-shot examples provide context to improve model performance:

```ruby
# Create few-shot examples
few_shot_examples = [
  DSPy::FewShotExample.new(
    input: { text: "I love this product!" },
    output: { sentiment: "positive", confidence: 0.95 },
    reasoning: "The phrase 'I love' indicates strong positive sentiment."
  ),
  DSPy::FewShotExample.new(
    input: { text: "This is terrible." },
    output: { sentiment: "negative", confidence: 0.9 },
    reasoning: "The word 'terrible' clearly indicates negative sentiment."
  )
]

# Use with predictor
predictor = DSPy::Predict.new(ClassifyText)
optimized_predictor = predictor.with_examples(few_shot_examples)

result = optimized_predictor.call(text: "This movie was incredible!")
```

### Working with FewShotExample

```ruby
# Access FewShotExample properties
few_shot = DSPy::FewShotExample.new(
  input: { text: "Great product!" },
  output: { sentiment: "positive" },
  reasoning: "Positive language indicates good sentiment."
)

# Convert to hash
few_shot.to_h
# => { input: {...}, output: {...}, reasoning: "..." }

# Create from hash
few_shot = DSPy::FewShotExample.from_h({
  input: { text: "Bad experience" },
  output: { sentiment: "negative" },
  reasoning: "Negative words indicate poor sentiment"
})

# Generate prompt section
few_shot.to_prompt_section
# => "## Input\n```json\n{...}\n```\n## Reasoning\n...\n## Output\n```json\n{...}\n```"
```

### Serialization

```ruby
# Save and load examples
example = DSPy::Example.new(
  signature_class: ClassifyText,
  input: { text: "Sample text" },
  expected: { sentiment: ClassifyText::Sentiment::Positive, confidence: 0.8 },
  id: "example_1",
  metadata: { source: "manual", created_at: Time.current }
)

# Convert to hash for persistence
example_hash = example.to_h

# Recreate from hash
registry = { "ClassifyText" => ClassifyText }
reloaded_example = DSPy::Example.from_h(example_hash, signature_registry: registry)
```

## Testing Examples

```ruby
RSpec.describe DSPy::Example do
  let(:signature) { ClassifyText }
  
  describe "validation" do
    it "accepts valid examples" do
      example = DSPy::Example.new(
        signature_class: signature,
        input: { text: "Sample text" },
        expected: { 
          sentiment: ClassifyText::Sentiment::Positive,
          confidence: 0.8
        }
      )
      
      expect(example.input_values[:text]).to eq("Sample text")
      expect(example.expected_values[:sentiment]).to be_a(ClassifyText::Sentiment)
    end
    
    it "rejects invalid input types" do
      expect {
        DSPy::Example.new(
          signature_class: signature,
          input: { invalid_field: "value" },
          expected: { sentiment: ClassifyText::Sentiment::Positive, confidence: 0.8 }
        )
      }.to raise_error(ArgumentError)
    end
  end
end
```

### Integration with Evaluation

```ruby
# Examples work with the evaluation framework
examples = [
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "Great product!" },
    expected: { sentiment: ClassifyText::Sentiment::Positive, confidence: 0.9 }
  ),
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "Terrible service." },
    expected: { sentiment: ClassifyText::Sentiment::Negative, confidence: 0.8 }
  )
]

# Use with DSPy::Evaluate
predictor = DSPy::Predict.new(ClassifyText)
evaluator = DSPy::Evaluate.new(metric: :exact_match)

results = evaluator.evaluate(examples: examples) do |example|
  predictor.call(example.input_values)
end

puts results.score  # Accuracy score
```

## Usage with ChainOfThought

```ruby
# FewShotExamples can include reasoning for ChainOfThought
reasoning_examples = [
  DSPy::FewShotExample.new(
    input: { text: "I love this!" },
    output: { sentiment: "positive" },
    reasoning: "The phrase 'I love' shows strong positive emotion."
  )
]

# Use with ChainOfThought predictor
cot_predictor = DSPy::ChainOfThought.new(ClassifyText)
optimized_cot = cot_predictor.with_examples(reasoning_examples)

result = optimized_cot.call(text: "Amazing product!")
puts result.reasoning  # Will include step-by-step reasoning
```

## Best Practices

### 1. Balanced Examples

```ruby
# Ensure balanced representation across all output categories
def create_balanced_examples
  categories = ClassifyText::Sentiment.values
  examples_per_category = 20
  
  categories.flat_map do |sentiment|
    create_examples_for_sentiment(sentiment, count: examples_per_category)
  end
end
```

### 2. Include Edge Cases

```ruby
# Include edge cases and boundary conditions
edge_case_examples = [
  # Minimal text
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "Ok." },
    expected: { sentiment: ClassifyText::Sentiment::Neutral, confidence: 0.6 }
  ),
  
  # Mixed sentiment
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "I love the product but hate the price." },
    expected: { sentiment: ClassifyText::Sentiment::Neutral, confidence: 0.7 }
  )
]
```

### 3. Type Safety

```ruby
# Always ensure types match your signature
example = DSPy::Example.new(
  signature_class: ClassifyText,
  input: { text: "Sample text" },
  expected: { 
    sentiment: ClassifyText::Sentiment::Positive,  # Use enum, not string
    confidence: 0.8                                # Use Float, not String
  }
)
```

Examples provide the foundation for evaluation and few-shot prompting with type safety through Sorbet integration.