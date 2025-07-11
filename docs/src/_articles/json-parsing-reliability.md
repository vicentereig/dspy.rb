---
layout: post
title: "Stop Fighting JSON Parsing Errors in Your LLM Apps"
date: 2025-07-11
description: "How DSPy.rb's new reliability features make JSON extraction from LLMs actually reliable"
author: "Vicente Reig"
---

# Stop Fighting JSON Parsing Errors in Your LLM Apps

If you've built anything with LLMs, you know the pain. You carefully craft a prompt asking for JSON output, the model responds with something that *looks* like JSON, and then... `JSON::ParserError`. 

Maybe it wrapped the JSON in markdown code blocks. Maybe it added a helpful explanation before the actual data. Maybe it just forgot a comma. Whatever the reason, you're now debugging string manipulation instead of building features.

DSPy.rb just shipped reliability features that make this problem (mostly) go away.

## The Problem We're Solving

Here's what typically happens when you need structured data from an LLM:

```ruby
response = lm.chat(messages: [{
  role: "user", 
  content: "Extract product details as JSON: #{product_description}"
}])

# This works... sometimes
data = JSON.parse(response.content) # 💥 JSON::ParserError
```

You end up writing defensive code like this:

```ruby
# Please no more of this
json_match = response.content.match(/```json\n(.*?)\n```/m) || 
             response.content.match(/\{.*\}/m)
             
data = JSON.parse(json_match[1]) rescue nil
```

## The Solution: Provider-Optimized Strategies

DSPy.rb now automatically selects the best JSON extraction strategy based on your LLM provider and model. No configuration needed - it just works.

### For OpenAI Users

If you're using GPT-4 or GPT-4o, DSPy.rb automatically uses OpenAI's structured outputs:

```ruby
lm = DSPy::LM.new("openai/gpt-4o-mini", 
                  api_key: ENV["OPENAI_API_KEY"],
                  structured_outputs: true)

class ProductExtractor < DSPy::Signature
  output do
    const :name, String
    const :price, Float
    const :in_stock, T::Boolean
  end
end

# This now returns guaranteed valid JSON
predict = DSPy::Predict.new(ProductExtractor)
result = predict.forward(description: "iPhone 15 Pro - $999, available now")
# => { name: "iPhone 15 Pro", price: 999.0, in_stock: true }
```

No more parsing errors. OpenAI literally won't return invalid JSON when using structured outputs.

### For Anthropic Users

Claude users get the battle-tested 4-pattern extraction that handles Claude's various response formats:

```ruby
lm = DSPy::LM.new("anthropic/claude-3-haiku-20240307",
                  api_key: ENV["ANTHROPIC_API_KEY"])

# Same code, optimized extraction for Claude
predict = DSPy::Predict.new(ProductExtractor)
result = predict.forward(description: "MacBook Air M3 - $1199")
```

### For Everything Else

Models without special support get enhanced prompting that explicitly asks for clean JSON and tries multiple extraction patterns:

```ruby
# Works with any model
lm = DSPy::LM.new("ollama/llama2", base_url: "http://localhost:11434")
```

## Reliability Features That Actually Matter

### Automatic Retries with Fallback

Sometimes things fail. Networks hiccup. Models have bad days. DSPy.rb now retries intelligently:

1. **First attempt** with the optimal strategy
2. **Retry** with exponential backoff if parsing fails  
3. **Fallback** to the next best strategy if retries exhausted
4. **Progressive degradation** through all available strategies

This happens automatically. You don't need to configure anything.

### Smart Caching

Schema conversion and capability detection are now cached:

- **Schema caching**: OpenAI schemas cached for 1 hour
- **Capability caching**: Model capabilities cached for 24 hours
- **Thread-safe**: Works correctly in multi-threaded apps

This means the second request is always faster than the first.

### Better Error Messages

When things do go wrong, you get useful errors:

```
Failed to parse LLM response as JSON: unexpected token. 
Original content length: 156 chars
```

Not just "invalid JSON" - you get context to actually debug the issue.

## Configuration When You Need It

The defaults work well, but you can customize behavior:

```ruby
DSPy.configure do |config|
  # Control retry behavior
  config.structured_outputs.retry_enabled = true
  config.structured_outputs.max_retries = 3
  
  # Choose strategy: Strict (provider-optimized) or Compatible (enhanced prompting)
  config.structured_outputs.strategy = DSPy::Strategy::Strict
  # config.structured_outputs.strategy = DSPy::Strategy::Compatible
  
  # Disable delays in tests
  config.test_mode = true
end
```

## Real Performance Impact

In our testing with production workloads:

- **OpenAI + structured outputs**: 0% JSON parsing errors (down from ~5%)
- **Anthropic with extraction**: <0.1% errors (down from ~2%)
- **Enhanced prompting**: ~0.5% errors (down from ~8%)

The retry mechanism catches most remaining failures, bringing the effective error rate near zero for all providers.

## Migration is Seamless

If you're already using DSPy.rb, you get these improvements automatically. Your existing code continues to work, just more reliably:

```ruby
# Existing code - no changes needed
class SentimentAnalysis < DSPy::Signature
  output do
    const :sentiment, String
    const :confidence, Float
  end
end

# This is now more reliable
analyzer = DSPy::Predict.new(SentimentAnalysis)
result = analyzer.forward(text: "This library is amazing!")
```

## What's Next

This is part of our broader push to make DSPy.rb the most reliable way to build LLM applications in Ruby. We're focusing on:

1. **Streaming support** for real-time applications
2. **Batch processing** optimizations  
3. **Provider-specific optimizations** for Gemini, Cohere, and others

## Try It Now

```bash
gem install dspy
```

Or in your Gemfile:

```ruby
gem 'dspy', '~> 0.9.0'
```

Check out the [documentation](https://vicentereig.github.io/dspy.rb/) for more examples, or dive into the [reliability features guide](https://vicentereig.github.io/dspy.rb/production/) for advanced usage.

---

*Building something cool with DSPy.rb? I'd love to hear about it - [@vicentereig](https://twitter.com/vicentereig)*