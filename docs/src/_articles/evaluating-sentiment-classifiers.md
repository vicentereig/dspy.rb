---
layout: article
title: "Evaluating Sentiment Classifiers: Beyond Simple Accuracy"
description: "Learn how to systematically evaluate LLM applications using DSPy.rb's evaluation framework, from basic metrics to advanced quality assessment."
date: 2024-12-19
author: DSPy.rb Team
categories: [evaluation, sentiment-analysis, tutorial]
featured: true
---

# Evaluating Sentiment Classifiers: Beyond Simple Accuracy

Building a sentiment classifier is one thing. Knowing if it actually works well is another. In this tutorial, we'll walk through DSPy.rb's evaluation framework using a practical sentiment classification example that goes beyond simple accuracy.

## What We're Building

We'll create a tweet sentiment classifier that:
- Classifies tweets as positive, negative, or neutral
- Provides confidence scores and reasoning
- Gets evaluated using multiple metrics to understand its true performance

## Setting Up the Classifier

First, let's define our signature. This is where DSPy.rb's type safety really shines:

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
    const :tweet, String, description: "The tweet text to analyze"
  end

  output do
    const :sentiment, Sentiment, description: "The sentiment classification"
    const :confidence, Float, description: "Confidence score between 0.0 and 1.0"
    const :reasoning, String, description: "Brief explanation of the classification"
  end
end
```

The enum ensures we only get valid sentiments back, and the additional fields (confidence and reasoning) give us more data to work with during evaluation.

Now let's wrap it in a module that uses chain-of-thought reasoning:

```ruby
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

## Creating Test Data

For this example, we'll generate some synthetic tweet data. In a real application, you'd want to use actual tweets with human-labeled sentiments:

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
  # ... more examples
]
```

## Evaluation Level 1: Basic Accuracy

Let's start with the simplest evaluation - exact match on the sentiment field:

```ruby
# Configure DSPy
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

classifier = SentimentClassifier.new

# Basic evaluation
basic_metric = DSPy::Metrics.exact_match(field: :sentiment)
basic_evaluator = DSPy::Evaluate.new(classifier, metric: basic_metric)

result = basic_evaluator.evaluate(test_examples, display_progress: true)
puts "Accuracy: #{(result.score * 100).round(1)}%"
```

This gives us a baseline - what percentage of tweets did we classify correctly? But there's a catch here: the built-in `exact_match` expects string values, but our signature returns an enum. So we need something smarter.

## Evaluation Level 2: Custom Metrics

Let's create a custom metric that properly handles our enum types:

```ruby
def sentiment_accuracy_metric
  ->(example, prediction) do
    return false unless prediction && prediction.respond_to?(:sentiment)
    
    expected_sentiment = example.dig(:expected, :sentiment)
    actual_sentiment = prediction.sentiment.serialize  # Convert enum to string
    
    expected_sentiment == actual_sentiment
  end
end

# Use the custom metric
custom_evaluator = DSPy::Evaluate.new(classifier, metric: sentiment_accuracy_metric)
custom_result = custom_evaluator.evaluate(test_examples, display_progress: true)
```

This handles our enum correctly and gives us the true accuracy rate.

## Evaluation Level 3: Quality Assessment

Simple accuracy doesn't tell the whole story. Let's create a metric that considers multiple factors:

```ruby
def sentiment_quality_metric
  ->(example, prediction) do
    return 0.0 unless prediction
    
    score = 0.0
    
    # Base accuracy (50% of total score)
    expected_sentiment = example.dig(:expected, :sentiment)
    if prediction.sentiment.serialize == expected_sentiment
      score += 0.5
    end
    
    # Confidence appropriateness (30% of total score)
    if prediction.confidence
      expected_conf = example.dig(:expected, :confidence) || 0.5
      conf_diff = (prediction.confidence - expected_conf).abs
      conf_score = [1.0 - (conf_diff * 2), 0.0].max
      score += conf_score * 0.3
    end
    
    # Reasoning quality (20% of total score)
    if prediction.reasoning && 
       prediction.reasoning.length > 10 && 
       !prediction.reasoning.include?("I don't know")
      score += 0.2
    end
    
    score
  end
end
```

This metric rewards:
- **Correct classification** (50% weight) - the most important factor
- **Appropriate confidence** (30% weight) - being confident when right, uncertain when it's a tough call
- **Good reasoning** (20% weight) - providing substantial explanations

## Running the Evaluation

Here's how you'd run all three evaluations:

```ruby
# Quality evaluation
quality_evaluator = DSPy::Evaluate.new(classifier, metric: sentiment_quality_metric)
quality_result = quality_evaluator.evaluate(test_examples, display_progress: true)

puts "Quality Score: #{(quality_result.score * 100).round(1)}%"

# Analyze individual results
quality_result.results.each_with_index do |result, i|
  tweet = test_examples[i][:input][:tweet]
  expected = test_examples[i][:expected][:sentiment]
  
  puts "\nTweet: #{tweet[0..60]}..."
  puts "Expected: #{expected}"
  
  if result.prediction
    puts "Predicted: #{result.prediction.sentiment.serialize}"
    puts "Confidence: #{result.prediction.confidence.round(2)}"
    puts "Reasoning: #{result.prediction.reasoning[0..80]}..."
  else
    puts "❌ Prediction failed"
  end
  puts "Status: #{result.passed? ? '✅ PASS' : '❌ FAIL'}"
end
```

## Handling Errors Gracefully

Real-world data is messy. DSPy.rb's evaluation framework handles errors gracefully:

```ruby
error_evaluator = DSPy::Evaluate.new(
  classifier, 
  metric: sentiment_accuracy_metric,
  max_errors: 2,          # Stop after 2 errors
  provide_traceback: true # Include error details
)

# This won't crash even with problematic inputs
error_examples = [
  { input: { tweet: "" }, expected: { sentiment: "neutral" } },  # Empty tweet
  { input: { tweet: "Normal tweet" }, expected: { sentiment: "neutral" } }
]

result = error_evaluator.evaluate(error_examples, display_progress: true)

# Check which examples had errors
result.results.each do |r|
  if r.metrics[:error]
    puts "Error: #{r.metrics[:error]}"
  end
end
```

## What You Learn From This

Running this evaluation gives you insights like:

1. **Basic accuracy**: "We get 85% of sentiments right"
2. **Confidence calibration**: "We're overconfident on neutral tweets"
3. **Reasoning quality**: "Explanations are good for positive/negative but weak for neutral"
4. **Error patterns**: "Empty tweets cause failures"

## Key Takeaways

1. **Start simple, then add complexity**: Basic accuracy first, then custom metrics
2. **Multiple metrics tell a better story**: Accuracy + confidence + reasoning quality
3. **Handle failures gracefully**: Real applications need error handling
4. **Custom metrics are powerful**: Tailor evaluation to your specific domain

## Running the Complete Example

You can find the complete code in [`examples/sentiment-evaluation/sentiment_classifier.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/sentiment-evaluation/sentiment_classifier.rb). To run it:

```bash
export OPENAI_API_KEY=your-key-here
cd examples/sentiment-evaluation
ruby sentiment_classifier.rb
```

The evaluation framework is one of DSPy.rb's strongest features. It turns the usually-subjective process of "is my LLM app good?" into something measurable and systematic. Whether you're building sentiment classifiers, question-answering systems, or any other LLM application, proper evaluation is what separates experimental code from production-ready systems.