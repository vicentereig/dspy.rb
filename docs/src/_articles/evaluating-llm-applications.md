---
layout: blog
title: "Evaluating LLM Applications: From Basic Metrics to Custom Quality Assessment"
description: "Define acceptable program behavior with examples and metrics, inspect failures, and use the same evidence to optimize DSPy.rb programs."
date: 2025-06-01
author: Vicente Reig
tags: ["evaluation", "metrics", "testing", "quality"]
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/evaluating-llm-applications/"
image: /images/og/evaluating-llm-applications.png
---

An LLM program can return valid JSON and still be wrong. Evaluation defines the behavior you will accept: which examples matter, how predictions are scored, and which failures block a change.

DSPy.rb keeps that definition in ordinary Ruby. A program produces predictions, examples describe cases you care about, and a metric turns each prediction into evidence.

## The Evaluation Contract

Every evaluation needs three things:

1. A program to run.
2. Examples with representative inputs and, when available, expected outputs.
3. A metric that decides what counts as acceptable behavior.

The metric matters most. Exact match may be enough for a label. A generated report may need several bounded checks or a calibrated judge. A vague "quality" score only hides the decision you still need to make.

## A Sentiment Program

This example classifies tweets as positive, negative, or neutral. The complete version lives in `examples/sentiment-evaluation/`.

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
    const :tweet, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
    const :reasoning, String
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

The signature constrains the returned label to `TweetSentiment::Sentiment`. Correct labels and calibrated confidence require evidence from evaluation.

## Use Examples You Can Defend

Synthetic examples are useful for checking the evaluation code. They are weak evidence about production behavior. A real evaluation set should include human-reviewed examples, ambiguous cases, and inputs drawn from the distribution the program will see.

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

## Start With The Decision You Care About

The built-in exact-match metric compares one field. Because this prediction returns a `T::Enum`, the custom metric below serializes the enum before comparing it with the expected string:

```ruby
sentiment_accuracy = lambda do |example, prediction|
  expected = example.dig(:expected, :sentiment)
  actual = prediction&.sentiment&.serialize

  expected == actual
end

classifier = SentimentClassifier.new
evaluator = DSPy::Evals.new(classifier, metric: sentiment_accuracy)
result = evaluator.evaluate(test_examples)

puts "Accuracy: #{(result.pass_rate * 100).round(1)}%"
puts "Passed: #{result.passed_examples}/#{result.total_examples}"
```

`pass_rate` is the fraction of examples whose metric passed. `score` on the batch result is already expressed as a percentage; do not multiply it by 100 again.

## Return A Score When Pass/Fail Is Not Enough

A metric may return a hash with both a threshold decision and a normalized score. Name each component so a future reader can challenge it.

```ruby
sentiment_quality = lambda do |example, prediction|
  next { passed: false, score: 0.0 } unless prediction

  expected_label = example.dig(:expected, :sentiment)
  expected_confidence = example.dig(:expected, :confidence)

  label_score = prediction.sentiment.serialize == expected_label ? 1.0 : 0.0
  confidence_error = (prediction.confidence - expected_confidence).abs
  confidence_score = [1.0 - confidence_error, 0.0].max

  score = (label_score * 0.7) + (confidence_score * 0.3)
  {
    passed: label_score == 1.0 && confidence_error <= 0.2,
    score: score,
    label_score: label_score,
    confidence_error: confidence_error
  }
end

quality_result = DSPy::Evals.new(
  classifier,
  metric: sentiment_quality
).evaluate(test_examples)

average = quality_result.aggregated_metrics[:score_avg]
puts "Average score: #{(average * 100).round(1)}%"
```

The weights and the `0.2` confidence tolerance are policy choices. Validate them against human decisions before using them as a release gate. This metric also avoids text length as a proxy for reasoning quality; a longer explanation earns nothing by itself.

## Inspect Individual Failures

Aggregate scores tell you whether behavior moved. Per-example results tell you where.

```ruby
quality_result.results.each do |example_result|
  expected = example_result.example.dig(:expected, :sentiment)
  predicted = example_result.prediction&.sentiment&.serialize

  puts "Expected: #{expected}"
  puts "Predicted: #{predicted || '(no prediction)'}"
  puts "Score: #{example_result.metrics[:score].round(2)}"
  puts "Error: #{example_result.metrics[:error]}" if example_result.metrics[:error]
end
```

`DSPy::Evals` catches program and metric exceptions. `max_errors` stops scheduling new examples after too many failed results, while `provide_traceback` controls whether error results include backtrace entries.

```ruby
evaluator = DSPy::Evals.new(
  classifier,
  metric: sentiment_accuracy,
  max_errors: 3,
  provide_traceback: true
)
```

## Evaluation Drives Optimization

An optimizer uses the metric as its objective. It evaluates candidate program parameters, such as instructions and demonstrations supported by that optimizer, against your examples.

```ruby
program = DSPy::Predict.new(TweetSentiment)
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: sentiment_accuracy)

result = optimizer.compile(
  program,
  trainset: train_examples,
  valset: validation_examples
)

puts "Best validation score: #{result.best_score_value}"
optimized_program = result.optimized_program
```

An optimizer follows the objective you give it. Omit an important failure mode, or reward the wrong behavior, and the search will favor the wrong program.

## Run The Example

```bash
export OPENAI_API_KEY=your-api-key
bundle exec ruby examples/sentiment-evaluation/sentiment_classifier.rb
```

The repository example still uses a small synthetic set. Treat its output as a demonstration of the API, not as evidence that the classifier is ready for a particular application.

The [evaluation guide](/dspy.rb/optimization/evaluation/) covers the complete API. See [custom metrics](/dspy.rb/advanced/custom-metrics/) when a boolean comparison cannot express the behavior you need.
