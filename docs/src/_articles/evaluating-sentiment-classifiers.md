---
layout: blog
title: "Evaluating Sentiment Classifiers: Beyond Simple Accuracy"
description: "Build a sentiment evaluation that distinguishes label accuracy, confidence calibration, and execution failures."
date: 2025-06-01
author: Vicente Reig
categories: [evaluation, sentiment-analysis, tutorial]
featured: true
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/evaluating-sentiment-classifiers/"
image: /images/og/evaluating-sentiment-classifiers.png
---

A sentiment classifier can choose the right label and still be badly calibrated. It can also produce a valid enum for an input that should have been rejected. One accuracy number cannot describe all three behaviors.

This tutorial defines separate checks for classification, confidence, and execution. The complete example is in `examples/sentiment-evaluation/sentiment_classifier.rb`.

## Define The Program

The signature constrains the output shape. Evaluation checks whether those typed values are useful.

```ruby
class TweetSentiment < DSPy::Signature
  description "Classify the sentiment of tweets as positive, negative, or neutral"

  class Sentiment < T::Enum
    enums do
      Positive = new("positive")
      Negative = new("negative")
      Neutral = new("neutral")
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

## Assemble A Test Set

The examples below are synthetic. They make the tutorial reproducible, but they do not represent the ambiguity, slang, sarcasm, and distribution shifts of real social data.

```ruby
test_examples = [
  {
    input: { tweet: "Great weather for hiking today! Perfect temperature" },
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

For an application evaluation, replace these examples with reviewed data from the intended domain. Record disagreements between annotators rather than forcing uncertain cases into a clean label.

## Measure Label Accuracy

Configure the model and compare the serialized enum with the expected label:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    "openai/gpt-4o-mini",
    api_key: ENV["OPENAI_API_KEY"]
  )
end

classifier = SentimentClassifier.new

sentiment_accuracy = lambda do |example, prediction|
  expected = example.dig(:expected, :sentiment)
  actual = prediction&.sentiment&.serialize

  expected == actual
end

result = DSPy::Evals.new(
  classifier,
  metric: sentiment_accuracy
).evaluate(test_examples)

puts "Accuracy: #{(result.pass_rate * 100).round(1)}%"
```

The enum prevents an undeclared label from reaching application code. It does not make a declared label correct.

## Evaluate Confidence Separately

The expected confidence values in this tutorial are illustrative judgments. A real calibration test needs enough labeled predictions to compare confidence buckets with observed accuracy.

For a small example, return both the label decision and the confidence error:

```ruby
sentiment_quality = lambda do |example, prediction|
  next { passed: false, score: 0.0 } unless prediction

  expected_label = example.dig(:expected, :sentiment)
  expected_confidence = example.dig(:expected, :confidence)
  label_matches = prediction.sentiment.serialize == expected_label
  confidence_error = (prediction.confidence - expected_confidence).abs

  score = (label_matches ? 0.7 : 0.0) +
    ([1.0 - confidence_error, 0.0].max * 0.3)

  {
    passed: label_matches && confidence_error <= 0.2,
    score: score,
    label_matches: label_matches ? 1.0 : 0.0,
    confidence_error: confidence_error
  }
end
```

This metric states its policy: label correctness carries 70 percent of the score, and confidence must fall within `0.2` of the reference value to pass. Those choices should come from the application's cost of false positives, false negatives, and abstentions.

```ruby
quality_result = DSPy::Evals.new(
  classifier,
  metric: sentiment_quality
).evaluate(test_examples)

average = quality_result.aggregated_metrics[:score_avg]
puts "Average score: #{(average * 100).round(1)}%"
```

Do not use explanation length as a reasoning-quality metric. A long explanation can still be wrong, and hidden chain-of-thought is not required to evaluate the classifier's observable behavior.

## Inspect Failures

Each result keeps the example, prediction, pass decision, and metric data:

```ruby
quality_result.results.each do |example_result|
  tweet = example_result.example.dig(:input, :tweet)
  expected = example_result.example.dig(:expected, :sentiment)
  predicted = example_result.prediction&.sentiment&.serialize

  puts "Tweet: #{tweet}"
  puts "Expected: #{expected}"
  puts "Predicted: #{predicted || '(no prediction)'}"
  puts "Confidence error: #{example_result.metrics[:confidence_error]}"
  puts "Error: #{example_result.metrics[:error]}" if example_result.metrics[:error]
end
```

Program and metric exceptions become failed evaluation results. You can bound a run with `max_errors` and retain backtraces for diagnosis:

```ruby
evaluator = DSPy::Evals.new(
  classifier,
  metric: sentiment_quality,
  max_errors: 2,
  provide_traceback: true
)
```

An empty string is not guaranteed to raise an exception. If empty tweets are invalid in your application, validate that boundary explicitly and add an example that expects rejection.

## Run The Complete Example

```bash
export OPENAI_API_KEY=your-key
bundle exec ruby examples/sentiment-evaluation/sentiment_classifier.rb
```

The repository script demonstrates the evaluation API with synthetic data. Before using the metric as an optimization objective or deployment gate, replace its examples and thresholds with evidence from the application you are building.
