---
layout: blog
title: "Google Gemini Integration: Multimodal AI with Type-Safe Ruby"
description: "[DSPy.rb](https://github.com/vicentereig/dspy.rb) v0.20.0 introduces full Google Gemini support, bringing Google's state-of-the-art multimodal AI capabilities to Ruby developers with complete type safety and structured outputs."
date: 2025-08-26
author: "Vicente Reig"
category: "Features"
reading_time: "4 min read"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/introducing-google-gemini-support/"
---


A project outgrows you the moment the first contributor merges to `main`. I'm thrilled to announce that [DSPy.rb](https://github.com/vicentereig/dspy.rb) 
v0.20.0 brings complete support for Google Gemini! Thanks to the excellent work by Stefan Froelich ([@TheDumbTechGuy](https://github.com/thedumbtechguy)), 
you can now harness Google's cutting-edge multimodal AI models while maintaining all the type safety
and structured outputs that make [DSPy.rb](https://github.com/vicentereig/dspy.rb) unique.

## Why Google Gemini?

Google Gemini represents a significant leap in AI capabilities:
- **Multimodal by design** - Native support for text, images, and more
- **Advanced reasoning** - Superior performance on complex tasks
- **Competitive pricing** - Often more cost-effective than alternatives
- **Large context windows** - Handle extensive documents and conversations
- **Fast inference** - Quick response times for production workloads

With Gemini in [DSPy.rb](https://github.com/vicentereig/dspy.rb), you get access to these capabilities with Ruby's idiomatic patterns and complete type safety.

## Getting Started with Gemini

First, get your API key from [Google AI Studio](https://aistudio.google.com/):

1. Go to Google AI Studio
2. Create or select a project  
3. Generate an API key
4. Set your environment variable:

```bash
export GEMINI_API_KEY=your-api-key-here
```

Now you can use Gemini in [DSPy.rb](https://github.com/vicentereig/dspy.rb):

```ruby
require 'dspy'

# Configure DSPy with Gemini
DSPy.configure do |c|
  c.lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'])
end
```

## Available Models

[DSPy.rb](https://github.com/vicentereig/dspy.rb) supports all stable Gemini models from the official Google AI API:

### Latest Models (2025)
- **gemini-2.5-pro** - Latest flagship model with enhanced reasoning
- **gemini-2.5-flash** - Fast variant of the 2.5 series
- **gemini-2.5-flash-lite** - Lightweight version for high-throughput

### 2.0 Series (2024-2025)
- **gemini-2.0-flash** - Current fast model with multimodal capabilities
- **gemini-2.0-flash-lite** - Lightweight variant optimized for cost efficiency

### 1.5 Series (Production Ready)
- **gemini-1.5-pro** - Proven model for complex reasoning tasks
- **gemini-1.5-flash** - Fast, efficient model for most applications
- **gemini-1.5-flash-8b** - Smaller 8-billion parameter efficient variant

All Gemini models support multimodal inputs (text and images) natively.

**Note**: We only support stable models from the official API. Preview and experimental models are not included for reliability.

## Type-Safe Text Generation

Let's build a content analysis system that showcases Gemini's reasoning capabilities:

```ruby
class ContentAnalysis < DSPy::Signature
  description "Analyze written content for key insights and metrics"
  
  # Define enums for controlled outputs
  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative') 
      Neutral = new('neutral')
      Mixed = new('mixed')
    end
  end
  
  class ContentType < T::Enum
    enums do
      Article = new('article')
      BlogPost = new('blog_post')
      Review = new('review')
      SocialMedia = new('social_media')
      Academic = new('academic')
      Marketing = new('marketing')
    end
  end
  
  input do
    const :content, String
  end
  
  output do
    const :sentiment, Sentiment
    const :content_type, ContentType
    const :key_topics, T::Array[String]
    const :readability_score, Float  # 1-10 scale
    const :word_count, Integer
    const :main_idea, String
    const :target_audience, String
  end
end

# Create the analyzer
analyzer = DSPy::Predict.new(ContentAnalysis)

# Analyze some content
result = analyzer.forward(
  content: "Ruby has always been my favorite programming language. Its elegant " \
           "syntax and developer happiness philosophy make complex tasks feel " \
           "intuitive. The community support is incredible, and gems like [DSPy.rb](https://github.com/vicentereig/dspy.rb) " \
           "show how Ruby continues to innovate in the AI space."
)

# Access results with full type safety
puts "Sentiment: #{result.sentiment}"           # => Sentiment::Positive
puts "Type: #{result.content_type}"            # => ContentType::BlogPost  
puts "Topics: #{result.key_topics.join(', ')}" # => Ruby, programming, community
puts "Readability: #{result.readability_score}/10"
puts "Main idea: #{result.main_idea}"
```

## Multimodal Capabilities: Images + Text

Gemini's native multimodal support shines when analyzing images alongside text. Here's how to build an e-commerce product analyzer:

```ruby
class ProductImageAnalysis < DSPy::Signature
  description "Analyze product images to extract detailed information for e-commerce"
  
  class Condition < T::Enum
    enums do
      New = new('new')
      LikeNew = new('like_new') 
      Good = new('good')
      Fair = new('fair')
      Poor = new('poor')
    end
  end
  
  class Category < T::Enum
    enums do
      Electronics = new('electronics')
      Clothing = new('clothing')
      HomeGarden = new('home_garden')
      Sports = new('sports')
      Automotive = new('automotive')
      Books = new('books')
    end
  end
  
  input do
    const :product_image, DSPy::Image
    const :seller_description, String
  end
  
  output do
    const :category, Category
    const :condition, Condition
    const :brand, T.nilable(String)
    const :key_features, T::Array[String]
    const :colors, T::Array[String] 
    const :estimated_age, T.nilable(String)
    const :authenticity_concerns, T::Array[String]
    const :recommended_price_range, String
  end
end

# Load an image (from file as base64)
product_image = DSPy::Image.new(
  base64: Base64.strict_encode64(File.read('product_photo.jpg', mode: 'rb')),
  content_type: 'image/jpeg'
)

# Create the analyzer
analyzer = DSPy::Predict.new(ProductImageAnalysis)

# Analyze the product
result = analyzer.forward(
  product_image: product_image,
  seller_description: "Vintage leather jacket, worn a few times, great condition"
)

# Access multimodal analysis results
puts "Category: #{result.category}"
puts "Condition: #{result.condition}"
puts "Brand: #{result.brand || 'Unknown'}"
puts "Features: #{result.key_features.join(', ')}"
puts "Colors: #{result.colors.join(', ')}"
puts "Price range: #{result.recommended_price_range}"

if result.authenticity_concerns.any?
  puts "Authenticity concerns: #{result.authenticity_concerns.join('; ')}"
end
```

## Working with Multiple Images

Gemini can analyze multiple images simultaneously, perfect for comparative analysis:

```ruby
class ImageComparison < DSPy::Signature
  description "Compare multiple images and provide detailed analysis"
  
  input do
    const :images, T::Array[DSPy::Image]
    const :comparison_criteria, String
  end
  
  output do
    const :similarities, T::Array[String]
    const :differences, T::Array[String]
    const :quality_ranking, T::Array[Integer]  # Ranked by quality 1st, 2nd, etc.
    const :recommendation, String
  end
end

# Load multiple product images
images = [
  DSPy::Image.new(base64: Base64.strict_encode64(File.read('laptop1.jpg', mode: 'rb')), content_type: 'image/jpeg'),
  DSPy::Image.new(base64: Base64.strict_encode64(File.read('laptop2.jpg', mode: 'rb')), content_type: 'image/jpeg'), 
  DSPy::Image.new(base64: Base64.strict_encode64(File.read('laptop3.jpg', mode: 'rb')), content_type: 'image/jpeg')
]

comparator = DSPy::Predict.new(ImageComparison)

result = comparator.forward(
  images: images,
  comparison_criteria: "Compare these laptops for build quality, screen clarity, and overall condition"
)

puts "Similarities: #{result.similarities.join(', ')}"
puts "Differences: #{result.differences.join(', ')}"
puts "Quality ranking: #{result.quality_ranking}"
puts "Recommendation: #{result.recommendation}"
```

## Chain of Thought Reasoning

Gemini excels at complex reasoning tasks. Combine it with DSPy's Chain of Thought for transparent decision-making:

```ruby
class TechnicalDiagnostic < DSPy::Signature
  description "Diagnose technical issues with detailed reasoning"
  
  input do
    const :symptoms, String
    const :system_specs, String
    const :recent_changes, String
  end
  
  output do
    const :root_cause, String
    const :confidence_level, Float  # 0-1
    const :solution_steps, T::Array[String]
    const :prevention_tips, T::Array[String]
    const :escalation_needed, T::Boolean
  end
end

# Use Chain of Thought for transparent reasoning
diagnostic = DSPy::ChainOfThought.new(TechnicalDiagnostic)

result = diagnostic.forward(
  symptoms: "Application randomly crashes with memory errors after 2-3 hours",
  system_specs: "16GB RAM, Ruby 3.3, Rails 7.1, PostgreSQL 15",
  recent_changes: "Recently added image processing with ImageMagick"
)

# Access both the reasoning and the conclusion
puts "Reasoning process:"
puts result.reasoning
puts "\nRoot cause: #{result.root_cause}"
puts "Confidence: #{(result.confidence_level * 100).round}%"
puts "Solution steps:"
result.solution_steps.each_with_index do |step, i|
  puts "  #{i + 1}. #{step}"
end
```

## Advanced Configuration

### Custom Request Parameters

Generation parameters (temperature, top_p, top_k, max_output_tokens) are not currently supported at the DSPy API level for Gemini. The adapter accepts these parameters internally, but they're not exposed through the `forward()` method.

```ruby
# Standard configuration - no generation parameters at DSPy level
DSPy.configure do |c|
  c.lm = DSPy::LM.new('gemini/gemini-1.5-pro', api_key: ENV['GEMINI_API_KEY'])
end

predictor = DSPy::Predict.new(YourSignature)
result = predictor.forward(input: "Your input text")
```

For custom generation parameters, you would need to modify the adapter implementation directly, as neither `forward()` nor `raw_chat()` currently expose these parameters at the DSPy API level.

### Safety Filtering

Gemini includes built-in safety filtering that cannot be configured but provides helpful error handling:

```ruby
# Safety errors are automatically handled by the adapter
begin
  result = predictor.forward(input: "Your content")
rescue DSPy::LM::AdapterError => e
  if e.message.include?('blocked by safety filters')
    puts "Content was filtered for safety reasons"
    # Handle appropriately - perhaps rephrase or provide alternative content
  else
    raise e
  end
end
```

## Provider-Specific Features

### Image Format Support

Gemini supports base64-encoded images only (no URLs):

```ruby
# ✅ Works with Gemini
image = DSPy::Image.new(
  base64: base64_data,
  content_type: 'image/jpeg'  # png, gif, webp also supported
)

# ❌ Not supported by Gemini  
image = DSPy::Image.new(url: 'https://example.com/image.jpg')
```

### Token Usage Tracking

[DSPy.rb](https://github.com/vicentereig/dspy.rb) automatically tracks token usage for cost monitoring:

```ruby
# Access detailed usage information
adapter = lm.instance_variable_get(:@adapter)
response = adapter.chat(messages: [...])

puts "Input tokens: #{response.usage.input_tokens}"
puts "Output tokens: #{response.usage.output_tokens}" 
puts "Total tokens: #{response.usage.total_tokens}"

# Use for cost estimation
input_cost = response.usage.input_tokens * GEMINI_INPUT_RATE
output_cost = response.usage.output_tokens * GEMINI_OUTPUT_RATE
total_cost = input_cost + output_cost
```

## Performance Optimization Tips

1. **Model Selection**: Use `gemini-1.5-flash` for speed, `gemini-1.5-pro` for complex tasks
2. **Context Management**: Leverage Gemini's large context windows for comprehensive analysis
3. **Batch Processing**: Group related requests to minimize API overhead
4. **Streaming**: Use streaming for real-time applications (handled automatically)

```ruby
# Example: Environment-based model selection
DSPy.configure do |c|
  model = case Rails.env
          when 'development' then 'gemini/gemini-1.5-flash'    # Fast iteration
          when 'test' then 'gemini/gemini-1.5-flash'          # Consistent tests
          when 'production' then 'gemini/gemini-1.5-pro'      # Best quality
          end
          
  c.lm = DSPy::LM.new(model, api_key: ENV['GEMINI_API_KEY'])
end
```

## Error Handling

[DSPy.rb](https://github.com/vicentereig/dspy.rb) provides comprehensive error handling for Gemini:

```ruby
begin
  result = predictor.forward(input: "Your input")
rescue DSPy::LM::AdapterError => e
  case e.message
  when /authentication failed/
    puts "Check your GEMINI_API_KEY"
  when /rate limit/
    puts "Rate limited, retry with backoff"
  when /safety filters/
    puts "Content blocked by safety filters"
  when /image processing failed/
    puts "Image format or size issue"
  else
    puts "Unexpected error: #{e.message}"
  end
end
```

## Migration from Other Providers

Switching to Gemini is seamless - just change your LM configuration:

```ruby
# Before: OpenAI
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# After: Gemini
DSPy.configure do |c|
  c.lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'])
end

# Your signatures and predictors work exactly the same!
```

## What's Next?

Google Gemini support in [DSPy.rb](https://github.com/vicentereig/dspy.rb) v0.20.0 opens new possibilities:

- **Multimodal applications** with native image understanding
- **Cost optimization** with competitive pricing
- **Advanced reasoning** for complex problem-solving
- **Large context processing** for comprehensive analysis

The integration is production-ready with full error handling, usage tracking, and type safety. Special thanks to Stefan Froelich for making this integration possible!

## Get Started Today

```bash
# Update to [DSPy.rb](https://github.com/vicentereig/dspy.rb) v0.20.0
gem install dspy

# Set your API key
export GEMINI_API_KEY=your-key-here

# Start building with Gemini!
```

Ready to explore Google's cutting-edge AI capabilities in Ruby? The future of multimodal AI development is here! 🚀
