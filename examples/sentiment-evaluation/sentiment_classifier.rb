#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dspy'
require 'dotenv'
Dotenv.load(File.join(File.dirname(__FILE__), '..', '..', '.env'))

# Sentiment classification signature
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

# Enhanced sentiment classifier module
class SentimentClassifier < DSPy::Module
  def initialize
    super
    @predictor = DSPy::ChainOfThought.new(TweetSentiment)
  end

  def forward(tweet:)
    @predictor.call(tweet: tweet)
  end
end

# Generate synthetic training and test data
def generate_synthetic_data
  # Training examples with clear sentiment indicators
  training_examples = [
    { input: { tweet: "I absolutely love this new coffee shop! Best latte ever ☕️" }, 
      expected: { sentiment: "positive", confidence: 0.9 } },
    { input: { tweet: "This traffic is driving me crazy. Been stuck for 2 hours 😡" }, 
      expected: { sentiment: "negative", confidence: 0.8 } },
    { input: { tweet: "Just finished my morning jog. Weather is okay today." }, 
      expected: { sentiment: "neutral", confidence: 0.7 } },
    { input: { tweet: "Terrible customer service at the store. Never going back!" }, 
      expected: { sentiment: "negative", confidence: 0.9 } },
    { input: { tweet: "Amazing concert last night! The band was incredible 🎵" }, 
      expected: { sentiment: "positive", confidence: 0.9 } },
    { input: { tweet: "Meeting got moved to 3pm. Checking emails now." }, 
      expected: { sentiment: "neutral", confidence: 0.8 } },
    { input: { tweet: "So happy with my new phone! Camera quality is outstanding 📱" }, 
      expected: { sentiment: "positive", confidence: 0.8 } },
    { input: { tweet: "Disappointed with the movie. Plot was confusing and boring." }, 
      expected: { sentiment: "negative", confidence: 0.7 } }
  ]

  # Test examples for evaluation
  test_examples = [
    { input: { tweet: "Great weather for hiking today! Perfect temperature 🌞" }, 
      expected: { sentiment: "positive", confidence: 0.8 } },
    { input: { tweet: "Worst meal I've had in months. Cold food, slow service." }, 
      expected: { sentiment: "negative", confidence: 0.9 } },
    { input: { tweet: "Finished reading the book. It was okay, nothing special." }, 
      expected: { sentiment: "neutral", confidence: 0.6 } },
    { input: { tweet: "Thrilled about the promotion! Hard work finally paid off 🎉" }, 
      expected: { sentiment: "positive", confidence: 0.9 } },
    { input: { tweet: "Flight delayed again. This airline is unreliable." }, 
      expected: { sentiment: "negative", confidence: 0.8 } },
    { input: { tweet: "Grocery shopping done. Got everything on the list." }, 
      expected: { sentiment: "neutral", confidence: 0.8 } }
  ]

  [training_examples, test_examples]
end

# Custom sentiment accuracy metric
def sentiment_accuracy_metric
  ->(example, prediction) do
    return false unless prediction && prediction.respond_to?(:sentiment)
    
    expected_sentiment = example.dig(:expected, :sentiment) || example.dig('expected', 'sentiment')
    actual_sentiment = prediction.sentiment.serialize
    
    expected_sentiment == actual_sentiment
  end
end

# Advanced sentiment quality metric
def sentiment_quality_metric
  ->(example, prediction) do
    return 0.0 unless prediction
    
    score = 0.0
    
    # Base accuracy (50% weight)
    expected_sentiment = example.dig(:expected, :sentiment) || example.dig('expected', 'sentiment')
    if prediction.respond_to?(:sentiment) && prediction.sentiment.serialize == expected_sentiment
      score += 0.5
    end
    
    # Confidence appropriateness (30% weight)
    if prediction.respond_to?(:confidence) && prediction.confidence
      expected_conf = example.dig(:expected, :confidence) || example.dig('expected', 'confidence') || 0.5
      # Reward confidence that's close to expected
      conf_diff = (prediction.confidence - expected_conf).abs
      conf_score = [1.0 - (conf_diff * 2), 0.0].max  # Penalize large differences
      score += conf_score * 0.3
    end
    
    # Reasoning quality (20% weight) - check if reasoning is provided and substantial
    if prediction.respond_to?(:reasoning) && prediction.reasoning && 
       prediction.reasoning.length > 10 && !prediction.reasoning.include?("I don't know")
      score += 0.2
    end
    
    score
  end
end

def main
  # Configure DSPy
  unless ENV['OPENAI_API_KEY']
    puts "⚠️  OPENAI_API_KEY not set. This example requires an OpenAI API key."
    puts "Set it with: export OPENAI_API_KEY=your-key-here"
    exit 1
  end

  DSPy.configure do |c|
    c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
  end

  puts "🎭 Tweet Sentiment Classification Evaluation"
  puts "=" * 50

  # Create classifier
  classifier = SentimentClassifier.new

  # Generate synthetic data
  training_examples, test_examples = generate_synthetic_data

  puts "\n📊 Generated Data:"
  puts "Training examples: #{training_examples.size}"
  puts "Test examples: #{test_examples.size}"

  # 1. Basic Evaluation with Built-in Metric
  puts "\n1️⃣ Basic Evaluation (Exact Match)"
  puts "-" * 30

  basic_metric = DSPy::Metrics.exact_match(field: :sentiment)
  basic_evaluator = DSPy::Evals.new(classifier, metric: basic_metric)

  basic_result = basic_evaluator.evaluate(test_examples.first(3), display_progress: true)
  
  puts "Accuracy: #{(basic_result.score * 100).round(1)}%"
  puts "Passed: #{basic_result.passed_examples}/#{basic_result.total_examples}"

  # 2. Custom Accuracy Metric
  puts "\n2️⃣ Custom Sentiment Accuracy"
  puts "-" * 30

  custom_evaluator = DSPy::Evals.new(classifier, metric: sentiment_accuracy_metric)
  custom_result = custom_evaluator.evaluate(test_examples.first(4), display_progress: true)

  puts "Custom Accuracy: #{(custom_result.score * 100).round(1)}%"
  puts "Passed: #{custom_result.passed_examples}/#{custom_result.total_examples}"

  # 3. Advanced Quality Metric
  puts "\n3️⃣ Advanced Quality Assessment"
  puts "-" * 30

  quality_evaluator = DSPy::Evals.new(classifier, metric: sentiment_quality_metric)
  quality_result = quality_evaluator.evaluate(test_examples, display_progress: true)

  puts "Quality Score: #{(quality_result.score * 100).round(1)}%"
  puts "Passed: #{quality_result.passed_examples}/#{quality_result.total_examples}"

  # 4. Detailed Analysis
  puts "\n4️⃣ Detailed Result Analysis"
  puts "-" * 30

  quality_result.results.each_with_index do |result, i|
    tweet = test_examples[i][:input][:tweet]
    expected = test_examples[i][:expected][:sentiment]
    
    puts "\nTweet: #{tweet[0..60]}#{'...' if tweet.length > 60}"
    puts "Expected: #{expected}"
    
    if result.prediction
      puts "Predicted: #{result.prediction.sentiment.serialize}"
      puts "Confidence: #{result.prediction.confidence.round(2)}"
      puts "Quality Score: #{result.metrics.is_a?(Hash) ? result.metrics.values.first&.round(2) : result.metrics}"
    else
      puts "❌ Prediction failed"
    end
    puts "Status: #{result.passed? ? '✅ PASS' : '❌ FAIL'}"
  end

  # 5. Error Handling Example
  puts "\n5️⃣ Error Handling"
  puts "-" * 30

  # Add a problematic example
  error_examples = [
    { input: { tweet: "" }, expected: { sentiment: "neutral", confidence: 0.5 } },  # Empty tweet
    { input: { tweet: "Normal tweet about weather" }, expected: { sentiment: "neutral", confidence: 0.7 } }
  ]

  error_evaluator = DSPy::Evals.new(
    classifier, 
    metric: sentiment_accuracy_metric,
    max_errors: 2,
    provide_traceback: true
  )

  error_result = error_evaluator.evaluate(error_examples, display_progress: true)
  puts "Handled errors gracefully: #{error_result.results.any? { |r| r.metrics[:error] }}"

  puts "\n✅ Evaluation Complete!"
  puts "This example demonstrates:"
  puts "• Basic evaluation with built-in metrics"
  puts "• Custom metrics for domain-specific accuracy"
  puts "• Advanced multi-factor quality assessment"
  puts "• Error handling in evaluation pipelines"
  puts "• Detailed result analysis and reporting"
end

if __FILE__ == $0
  main
end