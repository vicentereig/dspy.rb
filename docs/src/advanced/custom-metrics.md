---
layout: docs
name: Custom Metrics
description: Define domain-specific evaluation metrics
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: Custom Metrics
  url: "/advanced/custom-metrics/"
prev:
  name: Retrieval Augmented Generation
  url: "/advanced/rag/"
next:
  name: Production
  url: "/production/"
date: 2025-07-10 00:00:00 +0000
---
# Custom Metrics

DSPy.rb's evaluation framework allows you to define custom metrics for domain-specific evaluation scenarios. While the framework provides basic built-in metrics, you can create sophisticated evaluation logic tailored to your specific use cases and business requirements.

## Overview

Custom metrics in DSPy.rb:
- **Proc-based Implementation**: Define metrics as Ruby procedures
- **Domain-specific Logic**: Create evaluation criteria specific to your use case
- **Flexible Scoring**: Support for boolean, numeric, and composite scoring
- **Integration**: Work seamlessly with DSPy's evaluation and optimization systems

## Basic Custom Metrics

### Simple Custom Metric

```ruby
# Define a custom accuracy metric
accuracy_metric = ->(example, prediction) do
  return false unless prediction && prediction.respond_to?(:answer)
  prediction.answer.downcase.strip == example.expected_answer.downcase.strip
end

# Use with evaluator
evaluator = DSPy::Evaluate.new(metric: accuracy_metric)

result = evaluator.evaluate(examples: test_examples) do |example|
  predictor.call(input: example.input)
end

puts "Custom accuracy: #{result.score}"
```

### Weighted Accuracy Metric

```ruby
# Metric that considers example difficulty/importance
weighted_accuracy = ->(example, prediction) do
  return false unless prediction && prediction.respond_to?(:answer)
  
  # Base correctness
  correct = prediction.answer.downcase.strip == example.expected_answer.downcase.strip
  return false unless correct
  
  # Apply weight based on example metadata
  weight = example.metadata[:difficulty] || 1.0
  
  # Return weighted score (true/false gets converted to 1.0/0.0)
  weight
end

# Use in evaluation
evaluator = DSPy::Evaluate.new(metric: weighted_accuracy)
```

### Confidence-Aware Metric

```ruby
# Metric that considers prediction confidence
confidence_metric = ->(example, prediction) do
  return 0.0 unless prediction
  
  # Check if prediction has required fields
  return 0.0 unless prediction.respond_to?(:answer) && prediction.respond_to?(:confidence)
  
  # Base accuracy
  correct = prediction.answer.downcase == example.expected_answer.downcase
  return 0.0 unless correct
  
  # Bonus for high confidence on correct answers
  base_score = 1.0
  confidence_bonus = prediction.confidence > 0.8 ? 0.2 : 0.0
  
  base_score + confidence_bonus
end
```

## Domain-Specific Metrics

### Customer Service Quality Metric

```ruby
customer_service_metric = ->(example, prediction) do
  return 0.0 unless prediction
  
  score = 0.0
  total_criteria = 5
  
  # Criterion 1: Answers the question
  if prediction.answer.downcase.include?(example.expected_keywords.map(&:downcase))
    score += 1.0
  end
  
  # Criterion 2: Professional tone
  unprofessional_words = ['stupid', 'dumb', 'whatever', 'i don\'t know']
  unless unprofessional_words.any? { |word| prediction.answer.downcase.include?(word) }
    score += 1.0
  end
  
  # Criterion 3: Helpful length (not too short, not too long)
  answer_length = prediction.answer.length
  if answer_length >= 50 && answer_length <= 500
    score += 1.0
  end
  
  # Criterion 4: Empathy/politeness
  polite_words = ['please', 'thank you', 'sorry', 'understand', 'apologize']
  if polite_words.any? { |word| prediction.answer.downcase.include?(word) }
    score += 1.0
  end
  
  # Criterion 5: Actionable advice
  action_words = ['try', 'can', 'will', 'should', 'recommend', 'suggest']
  if action_words.any? { |word| prediction.answer.downcase.include?(word) }
    score += 1.0
  end
  
  # Return normalized score
  score / total_criteria
end

# Use in evaluation
evaluator = DSPy::Evaluate.new(metric: customer_service_metric)
```

### Medical Information Accuracy Metric

```ruby
medical_accuracy_metric = ->(example, prediction) do
  return 0.0 unless prediction && prediction.respond_to?(:diagnosis)
  
  score = 0.0
  
  # Primary diagnosis match
  if prediction.diagnosis.downcase == example.expected_diagnosis.downcase
    score += 0.5
  end
  
  # Symptom coverage
  predicted_symptoms = prediction.symptoms || []
  expected_symptoms = example.expected_symptoms || []
  
  if expected_symptoms.any?
    covered_symptoms = predicted_symptoms & expected_symptoms
    symptom_coverage = covered_symptoms.size.to_f / expected_symptoms.size
    score += symptom_coverage * 0.3
  end
  
  # Safety check - penalize dangerous advice
  dangerous_phrases = ['ignore symptoms', 'don\'t see doctor', 'definitely not serious']
  if dangerous_phrases.any? { |phrase| prediction.answer.downcase.include?(phrase) }
    score = 0.0  # Fail completely for dangerous advice
  end
  
  # Confidence appropriateness
  if prediction.respond_to?(:confidence)
    # Penalize overconfidence on uncertain cases
    if example.metadata[:uncertainty] == 'high' && prediction.confidence > 0.9
      score *= 0.7
    end
  end
  
  score
end
```

### Financial Risk Assessment Metric

```ruby
financial_risk_metric = ->(example, prediction) do
  return 0.0 unless prediction
  
  total_score = 0.0
  weights = {
    risk_level: 0.4,
    reasoning: 0.3,
    recommendations: 0.2,
    compliance: 0.1
  }
  
  # Risk level accuracy
  if prediction.risk_level == example.expected_risk_level
    total_score += weights[:risk_level]
  elsif (prediction.risk_level == 'medium' && ['low', 'high'].include?(example.expected_risk_level))
    total_score += weights[:risk_level] * 0.5  # Partial credit for adjacent levels
  end
  
  # Reasoning quality
  reasoning_keywords = example.expected_reasoning_keywords || []
  if reasoning_keywords.any?
    mentioned_keywords = reasoning_keywords.select do |keyword|
      prediction.reasoning.downcase.include?(keyword.downcase)
    end
    keyword_coverage = mentioned_keywords.size.to_f / reasoning_keywords.size
    total_score += weights[:reasoning] * keyword_coverage
  end
  
  # Recommendation appropriateness
  if prediction.respond_to?(:recommendations)
    appropriate_recommendations = example.expected_recommendations || []
    if appropriate_recommendations.any?
      rec_match = (prediction.recommendations & appropriate_recommendations).size.to_f / appropriate_recommendations.size
      total_score += weights[:recommendations] * rec_match
    end
  end
  
  # Compliance check
  compliant = true
  prohibited_advice = ['guaranteed returns', 'no risk', 'insider information']
  prohibited_advice.each do |phrase|
    if prediction.reasoning.downcase.include?(phrase)
      compliant = false
      break
    end
  end
  
  total_score += weights[:compliance] if compliant
  
  total_score
end
```

## Multi-Objective Metrics

### Composite Quality Metric

```ruby
composite_quality_metric = ->(example, prediction) do
  return 0.0 unless prediction
  
  scores = {}
  
  # Accuracy component
  accuracy = prediction.answer.downcase == example.expected_answer.downcase ? 1.0 : 0.0
  scores[:accuracy] = accuracy
  
  # Completeness component
  required_points = example.required_points || []
  covered_points = required_points.select do |point|
    prediction.answer.downcase.include?(point.downcase)
  end
  completeness = required_points.empty? ? 1.0 : covered_points.size.to_f / required_points.size
  scores[:completeness] = completeness
  
  # Conciseness component (penalize excessive length)
  ideal_length = example.ideal_length || 200
  actual_length = prediction.answer.length
  length_ratio = actual_length.to_f / ideal_length
  conciseness = length_ratio <= 1.0 ? 1.0 : (1.0 / length_ratio)
  scores[:conciseness] = conciseness
  
  # Clarity component (based on readability heuristics)
  sentences = prediction.answer.split(/[.!?]+/)
  avg_sentence_length = sentences.map(&:split).map(&:size).sum.to_f / sentences.size
  clarity = avg_sentence_length <= 20 ? 1.0 : (20.0 / avg_sentence_length)
  scores[:clarity] = clarity
  
  # Weighted combination
  weights = {
    accuracy: 0.4,
    completeness: 0.3,
    conciseness: 0.15,
    clarity: 0.15
  }
  
  final_score = weights.map { |component, weight| scores[component] * weight }.sum
  
  # Store component scores for analysis
  prediction.instance_variable_set(:@component_scores, scores) if prediction.respond_to?(:instance_variable_set)
  
  final_score
end
```

### Business ROI Metric

```ruby
business_roi_metric = ->(example, prediction) do
  return 0.0 unless prediction
  
  # Calculate business value based on prediction quality
  base_value = 100.0  # Base value per correct prediction
  
  # Accuracy bonus
  accuracy_bonus = prediction.answer == example.expected_answer ? base_value : 0.0
  
  # Speed bonus (if prediction includes timing)
  speed_bonus = 0.0
  if prediction.respond_to?(:processing_time) && prediction.processing_time
    # Bonus for fast responses (under 2 seconds)
    speed_bonus = prediction.processing_time < 2.0 ? 25.0 : 0.0
  end
  
  # Confidence penalty for wrong answers
  confidence_penalty = 0.0
  if prediction.respond_to?(:confidence) && accuracy_bonus == 0.0
    # Penalty for being confidently wrong
    confidence_penalty = prediction.confidence > 0.8 ? -50.0 : 0.0
  end
  
  # Cost consideration
  estimated_cost = example.metadata[:estimated_cost] || 0.01
  cost_efficiency = accuracy_bonus > 0 ? (accuracy_bonus / estimated_cost) : 0.0
  
  total_value = accuracy_bonus + speed_bonus + confidence_penalty
  roi = cost_efficiency
  
  # Normalize to 0-1 scale for evaluation framework
  [roi / 1000.0, 1.0].min
end
```

## Evaluation with Custom Metrics

### Using Multiple Metrics

```ruby
# Define multiple metrics for comprehensive evaluation
metrics = {
  accuracy: ->(example, prediction) { 
    prediction.answer == example.expected_answer ? 1.0 : 0.0 
  },
  
  completeness: ->(example, prediction) {
    required_elements = example.required_elements || []
    return 1.0 if required_elements.empty?
    
    found_elements = required_elements.select do |element|
      prediction.answer.include?(element)
    end
    found_elements.size.to_f / required_elements.size
  },
  
  safety: ->(example, prediction) {
    unsafe_content = ['violence', 'harm', 'illegal']
    unsafe_found = unsafe_content.any? { |term| prediction.answer.downcase.include?(term) }
    unsafe_found ? 0.0 : 1.0
  }
}

# Evaluate with each metric
results = {}
metrics.each do |metric_name, metric_proc|
  evaluator = DSPy::Evaluate.new(metric: metric_proc)
  result = evaluator.evaluate(examples: test_examples) do |example|
    predictor.call(input: example.input)
  end
  results[metric_name] = result.score
end

puts "Evaluation Results:"
results.each do |metric, score|
  puts "  #{metric}: #{(score * 100).round(1)}%"
end
```

### Detailed Result Analysis

```ruby
def detailed_evaluation(predictor, test_examples)
  detailed_metric = ->(example, prediction) do
    result = {
      correct: prediction.answer == example.expected_answer,
      answer_length: prediction.answer.length,
      response_time: prediction.metadata[:response_time] || 0,
      confidence: prediction.confidence || 0
    }
    
    # Return 1.0 or 0.0 for the evaluator, but store details
    example.instance_variable_set(:@detailed_result, result)
    result[:correct] ? 1.0 : 0.0
  end
  
  evaluator = DSPy::Evaluate.new(metric: detailed_metric)
  evaluation_result = evaluator.evaluate(examples: test_examples) do |example|
    predictor.call(input: example.input)
  end
  
  # Extract detailed results
  detailed_results = test_examples.map do |example|
    example.instance_variable_get(:@detailed_result)
  end
  
  # Analyze patterns
  correct_results = detailed_results.select { |r| r[:correct] }
  incorrect_results = detailed_results.reject { |r| r[:correct] }
  
  analysis = {
    overall_accuracy: evaluation_result.score,
    avg_response_time: detailed_results.map { |r| r[:response_time] }.sum / detailed_results.size,
    avg_confidence_correct: correct_results.map { |r| r[:confidence] }.sum / correct_results.size,
    avg_confidence_incorrect: incorrect_results.empty? ? 0 : incorrect_results.map { |r| r[:confidence] }.sum / incorrect_results.size,
    avg_length_correct: correct_results.map { |r| r[:answer_length] }.sum / correct_results.size,
    avg_length_incorrect: incorrect_results.empty? ? 0 : incorrect_results.map { |r| r[:answer_length] }.sum / incorrect_results.size
  }
  
  analysis
end

# Usage
analysis = detailed_evaluation(predictor, test_examples)
puts "Detailed Analysis:"
puts "  Overall Accuracy: #{(analysis[:overall_accuracy] * 100).round(1)}%"
puts "  Avg Response Time: #{analysis[:avg_response_time].round(2)}s"
puts "  Confidence (Correct): #{analysis[:avg_confidence_correct].round(2)}"
puts "  Confidence (Incorrect): #{analysis[:avg_confidence_incorrect].round(2)}"
```

## Integration with Optimization

### Custom Metric in MIPROv2

```ruby
# Use custom metric in optimization
domain_specific_metric = ->(example, prediction) do
  # Your domain-specific evaluation logic
  score = evaluate_domain_quality(example, prediction)
  score
end

optimizer = DSPy::MIPROv2.new(signature: YourSignature)

result = optimizer.optimize(examples: training_examples) do |predictor, val_examples|
  evaluator = DSPy::Evaluate.new(metric: domain_specific_metric)
  evaluation_result = evaluator.evaluate(examples: val_examples) do |example|
    predictor.call(input: example.input)
  end
  evaluation_result.score
end

puts "Optimized for domain-specific quality: #{result.best_score_value}"
```

## Best Practices

### 1. Clear Scoring Logic

```ruby
# Good: Clear, documented scoring
sentiment_accuracy = ->(example, prediction) do
  return 0.0 unless prediction && prediction.respond_to?(:sentiment)
  
  # Exact match gets full score
  return 1.0 if prediction.sentiment == example.expected_sentiment
  
  # Partial credit for related sentiments
  sentiment_similarity = {
    ['positive', 'very_positive'] => 0.8,
    ['negative', 'very_negative'] => 0.8,
    ['neutral', 'mixed'] => 0.6
  }
  
  pair = [prediction.sentiment, example.expected_sentiment].sort
  sentiment_similarity[pair] || 0.0
end
```

### 2. Handle Edge Cases

```ruby
robust_metric = ->(example, prediction) do
  # Handle nil prediction
  return 0.0 unless prediction
  
  # Handle missing fields
  return 0.0 unless prediction.respond_to?(:answer)
  
  # Handle empty responses
  return 0.0 if prediction.answer.strip.empty?
  
  # Your actual evaluation logic
  prediction.answer.downcase == example.expected_answer.downcase ? 1.0 : 0.0
end
```

### 3. Consistent Return Values

```ruby
# Always return numeric values between 0 and 1
normalized_metric = ->(example, prediction) do
  raw_score = calculate_raw_score(example, prediction)
  
  # Normalize to 0-1 range
  max_possible_score = 10.0
  normalized = [raw_score / max_possible_score, 1.0].min
  [normalized, 0.0].max  # Ensure non-negative
end
```

### 4. Meaningful Metrics

```ruby
# Good: Metrics aligned with business goals
customer_satisfaction_metric = ->(example, prediction) do
  # Factors that actually matter for customer satisfaction
  factors = {
    solved_problem: prediction.answer.include?(example.solution_keywords.join(' ')),
    polite_tone: !prediction.answer.match?(/\b(stupid|dumb|obviously)\b/i),
    reasonable_length: prediction.answer.length.between?(50, 300),
    actionable: prediction.answer.match?(/\b(try|can|will|contact)\b/i)
  }
  
  # Weight based on customer feedback data
  weights = { solved_problem: 0.5, polite_tone: 0.2, reasonable_length: 0.15, actionable: 0.15 }
  
  factors.map { |factor, present| present ? weights[factor] : 0 }.sum
end
```

