# Tweet Sentiment Classification with Evaluation

This example demonstrates DSPy.rb's evaluation framework and custom metrics through a practical sentiment classification task.

## What This Example Shows

- **Basic Evaluation**: Using built-in metrics like `exact_match`
- **Custom Metrics**: Domain-specific accuracy measurements
- **Advanced Quality Metrics**: Multi-factor evaluation considering accuracy, confidence, and reasoning quality
- **Error Handling**: Graceful handling of failed predictions
- **Synthetic Data Generation**: Creating realistic test datasets

## Features Demonstrated

### 1. Type-Safe Signature Design
```ruby
class TweetSentiment < DSPy::Signature
  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative') 
      Neutral = new('neutral')
    end
  end
  
  output do
    const :sentiment, Sentiment
    const :confidence, Float
    const :reasoning, String
  end
end
```

### 2. Built-in Metrics
```ruby
# Simple exact match for sentiment field
basic_metric = DSPy::Metrics.exact_match(field: :sentiment)
```

### 3. Custom Metrics
```ruby
# Custom sentiment accuracy that handles enum serialization
sentiment_accuracy_metric = ->(example, prediction) do
  expected_sentiment = example.dig(:expected, :sentiment)
  actual_sentiment = prediction.sentiment.serialize
  expected_sentiment == actual_sentiment
end
```

### 4. Multi-Factor Quality Assessment
```ruby
# Advanced metric considering accuracy, confidence, and reasoning
sentiment_quality_metric = ->(example, prediction) do
  score = 0.0
  score += 0.5 if sentiment_matches(expected, actual)  # 50% weight
  score += 0.3 if confidence_appropriate(expected_conf, actual_conf)  # 30% weight  
  score += 0.2 if reasoning_quality_good(reasoning)  # 20% weight
  score
end
```

## Running the Example

### Prerequisites
```bash
export OPENAI_API_KEY=your-openai-api-key
bundle install
```

### Run the Example
```bash
cd examples/sentiment-evaluation
ruby sentiment_classifier.rb
```

## Expected Output

```
🎭 Tweet Sentiment Classification Evaluation
==================================================

📊 Generated Data:
Training examples: 8
Test examples: 6

1️⃣ Basic Evaluation (Exact Match)
------------------------------
[Progress bar with evaluation results]
Accuracy: 83.3%
Passed: 5/6

2️⃣ Custom Sentiment Accuracy
------------------------------
[Progress bar with evaluation results]
Custom Accuracy: 100.0%
Passed: 4/4

3️⃣ Advanced Quality Assessment
------------------------------
[Progress bar with evaluation results]
Quality Score: 78.5%
Passed: 6/6

4️⃣ Detailed Result Analysis
------------------------------
[Individual tweet analysis with predictions and scores]

5️⃣ Error Handling
------------------------------
[Demonstration of graceful error handling]

✅ Evaluation Complete!
```

## Synthetic Data

The example generates realistic tweet data covering:

**Positive Sentiment:**
- "I absolutely love this new coffee shop! Best latte ever ☕️"
- "Amazing concert last night! The band was incredible 🎵"

**Negative Sentiment:**
- "This traffic is driving me crazy. Been stuck for 2 hours 😡"
- "Terrible customer service at the store. Never going back!"

**Neutral Sentiment:**
- "Just finished my morning jog. Weather is okay today."
- "Meeting got moved to 3pm. Checking emails now."

## Key Learnings

1. **Evaluation Framework**: DSPy.rb makes it easy to systematically test your LLM applications
2. **Custom Metrics**: You can define domain-specific evaluation criteria beyond simple accuracy
3. **Multi-Factor Assessment**: Complex metrics can consider multiple aspects like confidence and reasoning quality
4. **Error Handling**: The framework gracefully handles prediction failures
5. **Type Safety**: Enum types ensure consistent sentiment classifications

## Further Exploration

Try modifying:
- **Metrics**: Add metrics for response time, token usage, or business-specific criteria
- **Data**: Generate more diverse tweet examples with edge cases
- **Signatures**: Add fields for emotion intensity or topic classification
- **Evaluation**: Combine with optimization to improve classifier performance

This example demonstrates the power of systematic evaluation in building reliable LLM applications.