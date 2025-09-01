---
layout: docs
name: Prompt Optimization
description: Programmatically optimize prompts for better performance
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: Prompt Optimization
  url: "/optimization/prompt-optimization/"
prev:
  name: Evaluation Framework
  url: "/optimization/evaluation/"
next:
  name: MIPROv2 Optimizer
  url: "/optimization/miprov2/"
date: 2025-07-10 00:00:00 +0000
---
# Prompt Optimization

DSPy.rb treats prompts as first-class objects that can be manipulated, analyzed, and optimized programmatically. Rather than hand-crafting prompt strings, you work with structured prompt objects that contain instructions, few-shot examples, and schema information.

## Overview

DSPy.rb provides:
- **Prompt Objects**: Structured representation of prompts with instruction and examples
- **Programmatic Manipulation**: Methods to modify prompts systematically
- **Integration with Optimization**: Automatic prompt improvement through MIPROv2 and SimpleOptimizer
- **Schema Awareness**: Prompts understand input/output types from signatures

## Prompt Objects

### Basic Prompt Structure

```ruby
# Prompts are created automatically from signatures
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

# Create a predictor to access its prompt
predictor = DSPy::Predict.new(ClassifyText)
prompt = predictor.prompt

puts "Instruction: #{prompt.instruction}"
puts "Examples: #{prompt.few_shot_examples.size}"
puts "Schema: #{prompt.schema}"
```

### Prompt Components

```ruby
# A DSPy::Prompt contains:
prompt = predictor.prompt

# Core instruction
prompt.instruction
# => "Classify the sentiment of the given text"

# Few-shot examples
prompt.few_shot_examples
# => [#<DSPy::FewShotExample...>, ...]

# Input/output schema from signature
prompt.schema
# => { input: { text: String }, output: { sentiment: String, confidence: Float } }

# Formatted messages for LLM
prompt.to_messages
# => [{ role: "user", content: "..." }, ...]
```

## Manipulating Prompts

### Modifying Instructions

```ruby
# Create a new prompt with different instruction
new_prompt = prompt.with_instruction(
  "Analyze the emotional tone of the text and classify it as positive, negative, or neutral"
)

# Instructions can be refined iteratively
refined_prompt = new_prompt.with_instruction(
  "Carefully analyze the sentiment expressed in the text. Consider context, tone, and emotional indicators to classify as positive, negative, or neutral."
)
```

### Working with Few-Shot Examples

```ruby
# Create few-shot examples
examples = [
  DSPy::FewShotExample.new(
    input: { text: "I love this product!" },
    output: { sentiment: "positive", confidence: 0.9 }
  ),
  DSPy::FewShotExample.new(
    input: { text: "This is terrible quality." },
    output: { sentiment: "negative", confidence: 0.85 }
  ),
  DSPy::FewShotExample.new(
    input: { text: "It's an okay product." },
    output: { sentiment: "neutral", confidence: 0.7 }
  )
]

# Create new prompt with examples
enhanced_prompt = prompt.with_examples(examples)

# Add more examples
additional_examples = [
  DSPy::FewShotExample.new(
    input: { text: "Outstanding service!" },
    output: { sentiment: "positive", confidence: 0.95 }
  )
]

final_prompt = enhanced_prompt.with_examples(
  enhanced_prompt.few_shot_examples + additional_examples
)
```

### Combining Modifications

```ruby
# Chain modifications
optimized_prompt = prompt
  .with_instruction("Perform sentiment analysis on the given text")
  .with_examples(training_examples)

# Create predictor with custom prompt
custom_predictor = DSPy::Predict.new(ClassifyText)
custom_predictor.prompt = optimized_prompt
```

## Automatic Prompt Optimization

### Using MIPROv2 for Prompt Optimization

```ruby
# MIPROv2 automatically optimizes prompts
optimizer = DSPy::MIPROv2.new(signature: ClassifyText)

result = optimizer.optimize(examples: training_examples) do |predictor, val_examples|
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  evaluator.evaluate(examples: val_examples) do |example|
    predictor.call(text: example.text)
  end.score
end

# Access the optimized prompt
optimized_predictor = result.optimized_program
optimized_prompt = optimized_predictor.prompt

puts "Original instruction: #{predictor.prompt.instruction}"
puts "Optimized instruction: #{optimized_prompt.instruction}"
puts "Few-shot examples: #{optimized_prompt.few_shot_examples.size}"
```

### SimpleOptimizer for Quick Prompt Improvement

```ruby
# Quick prompt optimization
optimizer = DSPy::SimpleOptimizer.new(signature: ClassifyText)

result = optimizer.optimize(examples: training_examples) do |predictor, val_examples|
  # Custom evaluation logic
  correct = 0
  val_examples.each do |example|
    prediction = predictor.call(text: example.text)
    correct += 1 if prediction.sentiment == example.expected_sentiment
  end
  correct.to_f / val_examples.size
end

improved_prompt = result.optimized_program.prompt
```

## Prompt Analysis

### Analyzing Prompt Performance

```ruby
# Test different prompt variations
instructions = [
  "Classify the sentiment of this text",
  "Analyze the emotional tone and determine if it's positive, negative, or neutral",
  "Evaluate the sentiment expressed in the given text"
]

results = instructions.map do |instruction|
  test_prompt = prompt.with_instruction(instruction)
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = test_prompt
  
  # Evaluate performance
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  score = evaluator.evaluate(examples: test_examples) do |example|
    test_predictor.call(text: example.text)
  end.score
  
  { instruction: instruction, score: score }
end

# Find best instruction
best = results.max_by { |r| r[:score] }
puts "Best instruction: #{best[:instruction]}"
puts "Score: #{best[:score]}"
```

### Few-Shot Example Impact

```ruby
# Test impact of different numbers of examples
base_prompt = prompt.with_instruction("Classify sentiment as positive, negative, or neutral")

[0, 1, 3, 5, 8].each do |num_examples|
  test_examples_subset = training_examples.sample(num_examples)
  test_prompt = base_prompt.with_examples(test_examples_subset)
  
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = test_prompt
  
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  score = evaluator.evaluate(examples: validation_examples) do |example|
    test_predictor.call(text: example.text)
  end.score
  
  puts "#{num_examples} examples: #{score}"
end
```

## Prompt Generation

### Instruction Variations

```ruby
# Generate instruction variations for testing
base_instruction = "Classify the sentiment of the given text"

variations = [
  base_instruction,
  "Determine whether the text expresses positive, negative, or neutral sentiment",
  "Analyze the emotional tone of the text and categorize it",
  "Evaluate the sentiment conveyed in the provided text",
  "Assess the emotional polarity of the given text"
]

# Test each variation
best_instruction = nil
best_score = 0.0

variations.each do |instruction|
  test_prompt = prompt.with_instruction(instruction)
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = test_prompt
  
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  score = evaluator.evaluate(examples: test_examples) do |example|
    test_predictor.call(text: example.text)
  end.score
  
  if score > best_score
    best_score = score
    best_instruction = instruction
  end
end

puts "Best instruction: #{best_instruction}"
puts "Score: #{best_score}"
```

### Example Selection Strategies

```ruby
# Random selection
random_examples = training_examples.sample(5)

# Diverse selection (manual)
diverse_examples = [
  training_examples.find { |e| e.expected_sentiment == "positive" },
  training_examples.find { |e| e.expected_sentiment == "negative" },
  training_examples.find { |e| e.expected_sentiment == "neutral" },
  training_examples.find { |e| e.text.length > 100 },  # Long text
  training_examples.find { |e| e.text.length < 50 }    # Short text
].compact

# Compare strategies
strategies = {
  random: random_examples,
  diverse: diverse_examples
}

strategies.each do |strategy, examples|
  test_prompt = prompt.with_examples(examples)
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = test_prompt
  
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  score = evaluator.evaluate(examples: validation_examples) do |example|
    test_predictor.call(text: example.text)
  end.score
  
  puts "#{strategy} selection: #{score}"
end
```

## Advanced Prompt Techniques

### Progressive Prompting

```ruby
# Start simple, add complexity progressively
simple_prompt = prompt.with_instruction("Classify sentiment")

# Add details
detailed_prompt = simple_prompt.with_instruction(
  "Classify the sentiment of the text as positive, negative, or neutral. Consider the overall emotional tone and context."
)

# Add examples
enhanced_prompt = detailed_prompt.with_examples(training_examples.sample(3))

# Add confidence requirement
final_prompt = enhanced_prompt.with_instruction(
  "Classify the sentiment of the text as positive, negative, or neutral. Provide a confidence score between 0 and 1. Consider context, tone, and emotional indicators."
)

# Test progression
[simple_prompt, detailed_prompt, enhanced_prompt, final_prompt].each_with_index do |p, i|
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = p
  
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  score = evaluator.evaluate(examples: test_examples) do |example|
    test_predictor.call(text: example.text)
  end.score
  
  puts "Step #{i + 1}: #{score}"
end
```

### Context-Aware Prompting

```ruby
# Adapt prompts based on input characteristics
def create_adaptive_prompt(example)
  base_instruction = "Classify the sentiment of the text"
  
  # Adapt based on text length
  if example.text.length > 200
    instruction = "#{base_instruction}. This is a longer text, so consider the overall sentiment rather than individual phrases."
  elsif example.text.length < 50
    instruction = "#{base_instruction}. This is a short text, so focus on the key emotional indicators."
  else
    instruction = base_instruction
  end
  
  prompt.with_instruction(instruction)
end

# Use adaptive prompting
adaptive_scores = []
test_examples.each do |example|
  adaptive_prompt = create_adaptive_prompt(example)
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = adaptive_prompt
  
  prediction = test_predictor.call(text: example.text)
  correct = prediction.sentiment == example.expected_sentiment
  adaptive_scores << (correct ? 1.0 : 0.0)
end

adaptive_accuracy = adaptive_scores.sum / adaptive_scores.size
puts "Adaptive prompting accuracy: #{adaptive_accuracy}"
```

## Integration with Storage

### Saving Prompt Configurations

```ruby
# Save successful prompt configurations
if final_score > target_score
  prompt_config = {
    instruction: optimized_prompt.instruction,
    few_shot_examples: optimized_prompt.few_shot_examples.map(&:to_h),
    performance: final_score
  }
  
  storage_manager = DSPy::Storage::StorageManager.new
  saved_program = storage_manager.save_optimization_result(
    result,
    metadata: {
      prompt_config: prompt_config,
      optimization_method: 'manual_prompt_tuning'
    }
  )
  
  puts "Saved prompt configuration with ID: #{saved_program.program_id}"
end
```

### Loading and Reusing Prompts

```ruby
# Load previous optimization results
storage_manager = DSPy::Storage::StorageManager.new
previous_programs = storage_manager.find_programs(
  signature_class: 'ClassifyText'
)

if previous_programs.any?
  best_program = previous_programs.max_by { |p| p[:best_score] }
  saved_program = storage_manager.storage.load_program(best_program[:program_id])
  
  if saved_program.metadata[:prompt_config]
    # Recreate the optimized prompt
    config = saved_program.metadata[:prompt_config]
    
    reused_prompt = prompt
      .with_instruction(config[:instruction])
      .with_examples(config[:few_shot_examples].map { |ex| DSPy::FewShotExample.from_h(ex) })
    
    puts "Reusing optimized prompt with score: #{config[:performance]}"
  end
end
```

## Best Practices

### 1. Systematic Testing

```ruby
# Test prompts systematically
prompt_variants = [
  { instruction: "Base instruction", examples: [] },
  { instruction: "Detailed instruction", examples: [] },
  { instruction: "Base instruction", examples: training_examples.sample(3) },
  { instruction: "Detailed instruction", examples: training_examples.sample(3) }
]

results = prompt_variants.map do |variant|
  test_prompt = prompt
    .with_instruction(variant[:instruction])
    .with_examples(variant[:examples])
  
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = test_prompt
  
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  score = evaluator.evaluate(examples: test_examples) do |example|
    test_predictor.call(text: example.text)
  end.score
  
  variant.merge(score: score)
end

results.sort_by { |r| -r[:score] }.each do |result|
  puts "#{result[:score]}: #{result[:instruction]} (#{result[:examples].size} examples)"
end
```

### 2. Incremental Improvement

```ruby
# Improve prompts incrementally
current_prompt = prompt
current_score = baseline_score

improvements = [
  -> (p) { p.with_instruction("Improved instruction") },
  -> (p) { p.with_examples(training_examples.sample(2)) },
  -> (p) { p.with_examples(p.few_shot_examples + training_examples.sample(1)) }
]

improvements.each_with_index do |improvement, i|
  candidate_prompt = improvement.call(current_prompt)
  
  test_predictor = DSPy::Predict.new(ClassifyText)
  test_predictor.prompt = candidate_prompt
  
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  score = evaluator.evaluate(examples: test_examples) do |example|
    test_predictor.call(text: example.text)
  end.score
  
  if score > current_score
    current_prompt = candidate_prompt
    current_score = score
    puts "Improvement #{i + 1}: #{score}"
  else
    puts "No improvement from change #{i + 1}"
  end
end
```

### 3. Use Optimization Algorithms

```ruby
# Let MIPROv2 handle prompt optimization
optimizer = DSPy::MIPROv2.new(signature: ClassifyText, mode: :medium)

result = optimizer.optimize(examples: training_examples) do |predictor, val_examples|
  evaluator = DSPy::Evaluate.new(metric: :exact_match)
  evaluator.evaluate(examples: val_examples) do |example|
    predictor.call(text: example.text)
  end.score
end

# Use the automatically optimized prompt
optimized_prompt = result.optimized_program.prompt
puts "Automatically optimized instruction: #{optimized_prompt.instruction}"
puts "Automatically selected examples: #{optimized_prompt.few_shot_examples.size}"
```

