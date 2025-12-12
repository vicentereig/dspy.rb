---
layout: blog
title: "Run LLMs Locally with Ollama and Type-Safe Ruby"
description: "DSPy.rb now supports Ollama, bringing type-safe structured outputs to local LLM development. Learn how to build cost-effective AI applications with zero API charges during development."
date: 2025-07-28
author: "Vicente Reig"
category: "Features"
reading_time: "2 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/run-llms-locally-with-ollama-and-type-safe-ruby/"
image: /images/og/run-llms-locally-with-ollama-and-type-safe-ruby.png
---

I'm excited to announce that DSPy.rb v0.15.0 brings full support for Ollama! You can now run powerful language models locally while maintaining all the type safety and structured outputs that make DSPy.rb unique. This means zero API costs during development, complete data privacy, and the same great developer experience you expect from DSPy.

## Why Local LLMs Matter

Cloud-based LLMs are fantastic, but they come with trade-offs:
- **API costs** add up quickly during development and testing
- **Data privacy** concerns when processing sensitive information
- **Network latency** slows down rapid prototyping
- **Rate limits** can interrupt your development flow

With Ollama support in DSPy.rb, you get the best of both worlds: develop locally with zero costs, then deploy to production with your preferred cloud provider.

## Getting Started with Ollama

First, install Ollama from [ollama.com](https://ollama.com/) and pull a model:

```bash
# Install Ollama (macOS)
brew install ollama

# Start Ollama
ollama serve

# Pull a model
ollama pull llama3.2
```

Now you can use it in DSPy.rb just like any other provider:

```ruby
require 'dspy'

# Configure DSPy with Ollama - no API key needed!
DSPy.configure do |c|
  c.lm = DSPy::LM.new('ollama/llama3.2')
end
```

## Type-Safe Structured Outputs Work Seamlessly

Here's what makes DSPy.rb + Ollama special: you get the same type-safe, structured outputs as with cloud providers. Let's build a product categorization system:

```ruby
# Define a type-safe signature
class ProductAnalysis < DSPy::Signature
  description "Analyze product descriptions for e-commerce categorization"
  
  # Define enum for controlled categories
  class Category < T::Enum
    enums do
      Electronics = new('electronics')
      Clothing = new('clothing')
      HomeGarden = new('home_garden')
      Sports = new('sports')
      Books = new('books')
      Other = new('other')
    end
  end
  
  input do
    const :description, String
  end
  
  output do
    const :category, Category  # Type-safe enum
    const :confidence, Float   # 0.0 to 1.0
    const :keywords, T::Array[String]
    const :target_audience, String
  end
end

# Create the analyzer
analyzer = DSPy::Predict.new(ProductAnalysis)

# Analyze a product
result = analyzer.forward(
  description: "Lightweight aluminum laptop stand with adjustable height, " \
               "perfect for remote workers. Features cable management and " \
               "360-degree rotation. Compatible with MacBooks and PCs up to 17 inches."
)

# Access results with full type safety
puts "Category: #{result.category}"        # => Category::Electronics
puts "Confidence: #{result.confidence}"    # => 0.92
puts "Keywords: #{result.keywords.join(', ')}"
puts "Audience: #{result.target_audience}"

# The enum ensures only valid categories
case result.category
when ProductAnalysis::Category::Electronics
  puts "Route to electronics department"
when ProductAnalysis::Category::Clothing
  puts "Route to fashion department"
end
```

## Chain of Thought Reasoning

Ollama models excel at step-by-step reasoning. Here's how to use Chain of Thought with local models:

```ruby
class TechnicalSupport < DSPy::Signature
  description "Provide technical support with clear reasoning"
  
  input do
    const :issue, String
    const :system_info, String
  end
  
  output do
    const :diagnosis, String
    const :solution, String
    const :preventive_measures, T::Array[String]
  end
end

# Chain of Thought adds reasoning automatically
support = DSPy::ChainOfThought.new(TechnicalSupport)

result = support.forward(
  issue: "My Ruby app crashes with 'stack level too deep' error",
  system_info: "Ruby 3.3, Rails 7.1, PostgreSQL 15"
)

# Access the reasoning process
puts "Reasoning: #{result.reasoning}"
# => "This error typically indicates infinite recursion. Let me analyze:
#     1. The error occurs when method calls exceed Ruby's stack limit
#     2. Common causes include recursive methods without base cases
#     3. In Rails, this often happens with callbacks or associations..."

puts "Solution: #{result.solution}"
# => "Add a base case to your recursive method or use iteration instead..."
```

## Remote Ollama Instances

Need to share an Ollama instance across your team? DSPy.rb supports remote Ollama servers with optional authentication:

```ruby
# Connect to a remote Ollama instance
DSPy.configure do |c|
  c.lm = DSPy::LM.new('ollama/llama3.2',
    base_url: 'https://ollama.mycompany.com/v1',
    api_key: 'optional-auth-token'  # Only if your server requires auth
  )
end
```

## Cost Analysis: Development Savings

Let's look at the real savings during development. A typical development cycle involves running around 100 test iterations per day, with each test using roughly 500 input tokens and generating 200 output tokens. With GPT-4's pricing at $0.03 per 1K input tokens and $0.06 per 1K output tokens, this adds up to about $2.70 per day, or $81 per month just for development testing. With Ollama, your daily API cost drops to exactly zero – you're only paying for the electricity to run your machine.

## Performance Considerations

Local models have trade-offs, but DSPy.rb helps you optimize:

```ruby
# Development: Use fast local models
development_lm = DSPy::LM.new('ollama/llama3.2')  # 3B parameters, very fast

# Testing: Use larger local models
test_lm = DSPy::LM.new('ollama/llama3.1:70b')  # More accurate, slower

# Production: Use cloud providers
production_lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

# Easy environment-based switching
DSPy.configure do |c|
  c.lm = case Rails.env
         when 'development' then development_lm
         when 'test' then test_lm
         when 'production' then production_lm
         end
end
```

## What About Structured Output Support?

Ollama provides OpenAI-compatible endpoints, which means DSPy.rb's structured output strategies work out of the box. If a model doesn't fully support structured outputs, DSPy.rb automatically falls back to enhanced prompting strategies:

```ruby
# DSPy.rb automatically selects the best strategy
# 1. Try OpenAI-style structured outputs
# 2. Fall back to enhanced prompting if needed
# 3. Always return type-safe results

# You don't need to worry about this - it just works!
```

## Best Practices for Local Development

1. **Start Small**: Use smaller models (3B-7B parameters) for rapid iteration
2. **Test with Larger Models**: Validate with 13B+ models before production
3. **Use VCR for Tests**: Record LLM interactions for consistent test suites
4. **Monitor Performance**: Local models may be slower but have zero latency

```ruby
# Example: Recording tests with VCR
RSpec.describe ProductAnalyzer do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('ollama/llama3.2')
    end
  end

  it "categorizes products correctly", vcr: { cassette_name: "ollama/product_analysis" } do
    analyzer = DSPy::Predict.new(ProductAnalysis)
    result = analyzer.forward(description: "Blue running shoes with gel cushioning")
    
    expect(result.category).to eq(ProductAnalysis::Category::Sports)
    expect(result.confidence).to be > 0.8
  end
end
```

## Conclusion

Ollama support in DSPy.rb v0.15.0 brings the power of local LLMs to Ruby developers without sacrificing type safety or developer experience. Whether you're building prototypes, processing sensitive data, or just want to save on API costs, you can now enjoy the full DSPy.rb experience with models running on your own hardware.

Get started today:

```bash
# Install Ollama
brew install ollama  # or see ollama.com for other platforms

# Pull a model
ollama pull llama3.2

# Update DSPy.rb
bundle update dspy

# Start building!
```

The future of LLM development is hybrid: develop locally, deploy globally. With DSPy.rb and Ollama, that future is here today.

Happy coding! 🚀