---
layout: article
title: "Evaluating LLM Applications: From Basic Metrics to Custom Quality Assessment"
description: "Learn how to systematically test and measure your LLM applications using DSPy.rb's evaluation framework"
date: 2024-01-15
author: "DSPy.rb Team"
tags: ["evaluation", "metrics", "testing", "quality"]
---

# Evaluating LLM Applications: From Basic Metrics to Custom Quality Assessment

Building reliable LLM applications requires more than just getting them to work—you need to measure how well they work. DSPy.rb's evaluation framework makes it easy to systematically test your applications, from simple accuracy checks to sophisticated quality assessments.

## Why Evaluation Matters

When you're building with LLMs, "it works sometimes" isn't good enough for production. You need to know:

- **How accurate** is your classifier across different types of inputs?
- **How confident** should you be in the predictions?
- **What happens** when the LLM encounters edge cases?
- **How does performance change** when you modify prompts or switch models?

DSPy.rb's evaluation framework gives you concrete answers to these questions.

## The Evaluation Workflow

Every evaluation in DSPy.rb follows the same pattern:

1. **Define what you're testing** (your predictor)
2. **Choose how to measure success** (your metric)
3. **Run the evaluation** against test data
4. **Analyze the results**

Let's see this in action with a practical example.

## Example: Tweet Sentiment Classification

We'll build a sentiment classifier for tweets and show different ways to evaluate it. The complete example is available in [`examples/sentiment-evaluation/`](https://github.com/vicentereig/dspy.rb/tree/main/examples/sentiment-evaluation).

### 1. Define Your Task

First, we create a type-safe signature for sentiment classification:

```ruby
class TweetSentiment < DSPy::Signature
  description "Classify the sentiment of tweets as positive, negative, or neutral"

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative') 
      Neutral = new('neutral')
    end
  end

  input do
    const :tweet, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
    const :reasoning, String
  end
end

# Create a classifier module
class SentimentClassifier < DSPy::Module
  def initialize
    super
    @predictor = DSPy::ChainOfThought.new(TweetSentiment)
  end

  def forward(tweet:)
    @predictor.call(tweet: tweet)
  end
end
```

### 2. Create Test Data

For this example, we'll generate synthetic tweet data with known sentiments:

```ruby
test_examples = [
  { 
    input: { tweet: "Great weather for hiking today! Perfect temperature 🌞" }, 
    expected: { sentiment: "positive", confidence: 0.8 } 
  },
  { 
    input: { tweet: "Worst meal I've had in months. Cold food, slow service." }, 
    expected: { sentiment: "negative", confidence: 0.9 } 
  },
  { 
    input: { tweet: "Finished reading the book. It was okay, nothing special." }, 
    expected: { sentiment: "neutral", confidence: 0.6 } 
  }
]
```

## Basic Evaluation with Built-in Metrics

The simplest way to evaluate is using DSPy's built-in metrics:

```ruby
classifier = SentimentClassifier.new

# Use exact match for sentiment field
metric = DSPy::Metrics.exact_match(field: :sentiment)
evaluator = DSPy::Evaluate.new(classifier, metric: metric)

result = evaluator.evaluate(test_examples, display_progress: true)

puts "Accuracy: #{(result.score * 100).round(1)}%"
puts "Passed: #{result.passed_examples}/#{result.total_examples}"
```

This gives you a quick accuracy score, but sometimes you need more nuance.

## Custom Metrics for Domain-Specific Logic

Built-in metrics are great for common cases, but real applications often need custom logic. Here's how to create a custom metric that properly handles enum serialization:

```ruby
sentiment_accuracy_metric = ->(example, prediction) do
  return false unless prediction && prediction.respond_to?(:sentiment)
  
  expected_sentiment = example.dig(:expected, :sentiment)
  actual_sentiment = prediction.sentiment.serialize
  
  expected_sentiment == actual_sentiment
end

custom_evaluator = DSPy::Evaluate.new(classifier, metric: sentiment_accuracy_metric)
custom_result = custom_evaluator.evaluate(test_examples, display_progress: true)
```

Custom metrics give you full control over what "correct" means in your domain.

## Advanced Multi-Factor Quality Assessment

Sometimes accuracy isn't enough. You might want to evaluate multiple aspects of the prediction. Here's an advanced metric that considers accuracy, confidence appropriateness, and reasoning quality:

```ruby
sentiment_quality_metric = ->(example, prediction) do
  return 0.0 unless prediction
  
  score = 0.0
  
  # Base accuracy (50% weight)
  expected_sentiment = example.dig(:expected, :sentiment)
  if prediction.respond_to?(:sentiment) && prediction.sentiment.serialize == expected_sentiment
    score += 0.5
  end
  
  # Confidence appropriateness (30% weight)
  if prediction.respond_to?(:confidence) && prediction.confidence
    expected_conf = example.dig(:expected, :confidence) || 0.5
    conf_diff = (prediction.confidence - expected_conf).abs
    conf_score = [1.0 - (conf_diff * 2), 0.0].max
    score += conf_score * 0.3
  end
  
  # Reasoning quality (20% weight)
  if prediction.respond_to?(:reasoning) && prediction.reasoning && 
     prediction.reasoning.length > 10
    score += 0.2
  end
  
  score
end
```

This metric gives you a comprehensive quality score that considers multiple factors:

```ruby
quality_evaluator = DSPy::Evaluate.new(classifier, metric: sentiment_quality_metric)
quality_result = quality_evaluator.evaluate(test_examples, display_progress: true)

puts "Quality Score: #{(quality_result.score * 100).round(1)}%"
```

## Detailed Result Analysis

The evaluation framework doesn't just give you aggregate scores—you can dive into individual predictions:

```ruby
quality_result.results.each_with_index do |result, i|
  tweet = test_examples[i][:input][:tweet]
  expected = test_examples[i][:expected][:sentiment]
  
  puts "Tweet: #{tweet[0..60]}..."
  puts "Expected: #{expected}"
  
  if result.prediction
    puts "Predicted: #{result.prediction.sentiment.serialize}"
    puts "Confidence: #{result.prediction.confidence.round(2)}"
    puts "Quality Score: #{result.metrics.round(2)}"
  end
  
  puts "Status: #{result.passed? ? '✅ PASS' : '❌ FAIL'}"
  puts ""
end
```

This gives you insight into which types of examples your model handles well and which ones need improvement.

## Error Handling

Real applications need to handle failures gracefully. The evaluation framework makes this easy:

```ruby
error_evaluator = DSPy::Evaluate.new(
  classifier, 
  metric: sentiment_accuracy_metric,
  max_errors: 3,           # Stop after 3 errors
  provide_traceback: true  # Include stack traces for debugging
)

result = error_evaluator.evaluate(test_examples)

# Check for errors
error_count = result.results.count { |r| r.metrics[:error] }
puts "#{error_count} examples failed with errors"
```

## Integration with Optimization

The real power comes when you combine evaluation with optimization. You can use your custom metrics to guide prompt improvement:

```ruby
optimizer = DSPy::MIPROv2.new(signature: TweetSentiment)

result = optimizer.optimize(examples: train_examples) do |candidate_predictor, val_examples|
  evaluator = DSPy::Evaluate.new(candidate_predictor, metric: sentiment_quality_metric)
  evaluation_result = evaluator.evaluate(val_examples, display_progress: false)
  evaluation_result.score  # This guides the optimization
end

puts "Best optimized quality score: #{result.best_score_value}"
```

## Running the Complete Example

The full working example is available in the repository. To try it:

```bash
export OPENAI_API_KEY=your-api-key
cd examples/sentiment-evaluation
ruby sentiment_classifier.rb
```

You'll see output like:

```
🎭 Tweet Sentiment Classification Evaluation
==================================================

1️⃣ Basic Evaluation (Exact Match)
Accuracy: 83.3%

2️⃣ Custom Sentiment Accuracy  
Custom Accuracy: 100.0%

3️⃣ Advanced Quality Assessment
Quality Score: 78.5%

4️⃣ Detailed Result Analysis
[Individual predictions with reasoning]

5️⃣ Error Handling
[Graceful error handling demonstration]
```

## Key Takeaways

1. **Start Simple**: Begin with built-in metrics like `exact_match` to get baseline accuracy
2. **Add Domain Logic**: Create custom metrics that understand your specific requirements
3. **Consider Multiple Factors**: Advanced metrics can evaluate accuracy, confidence, reasoning quality, and more
4. **Handle Errors Gracefully**: Production systems need robust error handling
5. **Integrate with Optimization**: Use evaluation metrics to guide automated prompt improvement

## Next Steps

The evaluation framework supports many more features:

- **Multiple Metrics**: Run several metrics simultaneously for comprehensive assessment
- **Batch Processing**: Evaluate large datasets efficiently
- **Integration with CI/CD**: Automate evaluation in your deployment pipeline
- **Comparison Testing**: Compare different models, prompts, or configurations

Check out the [comprehensive evaluation guide](/optimization/evaluation/) and [custom metrics documentation](/advanced/custom-metrics/) for more advanced techniques.

Systematic evaluation is the foundation of reliable LLM applications. With DSPy.rb's evaluation framework, you can move from "it seems to work" to "I know exactly how well it works"—and that makes all the difference in production.