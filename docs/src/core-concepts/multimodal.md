---
layout: docs
title: Multimodal Support
description: Process images and text with DSPy.rb's multimodal capabilities. Support
  for OpenAI and Anthropic vision models with type-safe image analysis and structured
  outputs.
nav_order: 7
parent: Core Concepts
date: 2025-08-13 00:00:00 +0000
last_modified_at: 2025-08-26 00:00:00 +0000
---
# Multimodal Support

DSPy.rb supports multimodal inputs, allowing you to work with both text and images in your AI applications. This feature enables powerful use cases like image analysis, visual question answering, and object detection.

## Vision-Capable Models

### OpenAI Models
- `gpt-4-vision-preview`
- `gpt-4-turbo`
- `gpt-4o` and `gpt-4o-mini`

### Anthropic Models
- Claude 3 series (Opus, Sonnet, Haiku)
- Claude 3.5 series (Sonnet, Haiku)
- Claude 4 (latest)

### Google Gemini Models
- `gemini-1.5-flash` (fast, efficient)
- `gemini-1.5-pro` (advanced reasoning)
- `gemini-1.0-pro` (previous generation)

## Working with Images

### Creating Images

DSPy.rb provides the `DSPy::Image` class for handling images in various formats:

```ruby
# From URL (OpenAI only)
image = DSPy::Image.new(
  url: 'https://example.com/image.jpg'
)

# From base64 data (both providers)
image = DSPy::Image.new(
  base64: 'iVBORw0KGgoAAAANSUh...', # your base64 string
  content_type: 'image/jpeg'
)

# From byte array (both providers)
File.open('image.jpg', 'rb') do |file|
  image = DSPy::Image.new(
    data: file.read,
    content_type: 'image/jpeg'
  )
end

# With detail level (OpenAI only)
image = DSPy::Image.new(
  url: 'https://example.com/image.jpg',
  detail: 'high'  # 'low', 'high', or 'auto'
)
```

### Supported Formats
- JPEG (`image/jpeg`)
- PNG (`image/png`)
- GIF (`image/gif`)
- WebP (`image/webp`)

### Size Limits
- Maximum size: 5MB per image
- Multiple images: Supported (counts toward token usage)

## Using Images with LM

### Simple Image Analysis

```ruby
# Initialize with a vision-capable model
lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])

# Create an image
image = DSPy::Image.new(url: 'https://example.com/photo.jpg')

# Analyze the image
response = lm.raw_chat do |messages|
  messages.user_with_image('What is in this image?', image)
end

puts response
```

### Multiple Images

```ruby
image1 = DSPy::Image.new(url: 'https://example.com/before.jpg')
image2 = DSPy::Image.new(url: 'https://example.com/after.jpg')

response = lm.raw_chat do |messages|
  messages.user_with_images(
    'What changed between these two images?',
    [image1, image2]
  )
end
```

### With System Prompts

```ruby
response = lm.raw_chat do |messages|
  messages.system('You are an expert art critic.')
  messages.user_with_image('Analyze this painting.', image)
end
```

## Structured Multimodal Signatures

DSPy.rb supports powerful structured signatures that can analyze images and extract detailed information with type safety.

### Image Analysis with Structured Output

Extract comprehensive information from images including colors, objects, mood, and more:

```ruby
class ImageAnalysis < DSPy::Signature
  description "Analyze images comprehensively to extract objects, colors, mood, and style"

  class DetailLevel < T::Enum
    enums do
      Brief = new('brief')
      Standard = new('standard')
      Detailed = new('detailed')
    end
  end

  input do
    const :image, DSPy::Image, description: 'Image to analyze'
    const :focus, String, default: 'general', description: 'Analysis focus'
    const :detail_level, DetailLevel, default: DetailLevel::Standard, description: 'Level of detail'
  end
  
  output do
    const :description, String, description: 'Overall description of the image'
    const :objects, T::Array[String], description: 'List of objects detected'
    const :dominant_colors, T::Array[String], description: 'Main colors in the image'
    const :mood, String, description: 'Overall mood or atmosphere'
    const :style, String, description: 'Artistic style or characteristics'
    const :lighting, String, description: 'Description of lighting conditions'
    const :confidence, Float, description: 'Analysis confidence (0.0-1.0)'
  end
end

# Usage
analyzer = DSPy::Predict.new(ImageAnalysis)
image = DSPy::Image.new(url: 'https://example.com/landscape.jpg')
analysis = analyzer.call(
  image: image,
  focus: 'colors',
  detail_level: ImageAnalysis::DetailLevel::Detailed
)

puts analysis.description
puts "Colors: #{analysis.dominant_colors.join(', ')}"
puts "Mood: #{analysis.mood}"
puts "Objects: #{analysis.objects.join(', ')}"
```

### Object Detection with Type-Safe Bounding Boxes

Use `T::Struct` for type-safe bounding box detection:

```ruby
# Define structured types
class BoundingBox < T::Struct
  const :x, Float
  const :y, Float
  const :width, Float
  const :height, Float
end

class DetectedObject < T::Struct
  const :label, String
  const :bbox, BoundingBox
  const :confidence, Float
end

class BoundingBoxDetection < DSPy::Signature
  description "Detect and locate objects in images with normalized bounding box coordinates"

  class DetailLevel < T::Enum
    enums do
      Basic = new('basic')
      Standard = new('standard')
      Detailed = new('detailed')
    end
  end

  input do
    const :query, T.any(String, NilClass), description: 'Object to detect'
    const :image, DSPy::Image, description: 'Image to analyze for object detection'
    const :detail_level, DetailLevel, default: DetailLevel::Standard, description: 'Detection detail level'
  end
  
  output do
    const :objects, T::Array[DetectedObject], description: 'Detected objects with bounding boxes'
    const :count, Integer, description: 'Total number of objects detected'
    const :confidence, Float, description: 'Overall detection confidence'
  end
end

# Usage with type safety
detector = DSPy::Predict.new(BoundingBoxDetection)
image = DSPy::Image.new(url: 'https://example.com/aerial-image.jpg')
detection = detector.call(
  query: 'airplanes',
  image: image,
  detail_level: BoundingBoxDetection::DetailLevel::Standard
)

detection.objects.each do |obj|
  puts "#{obj.label} at (#{obj.bbox.x}, #{obj.bbox.y})"
  puts "Size: #{obj.bbox.width} x #{obj.bbox.height}"
  puts "Confidence: #{(obj.confidence * 100).round(1)}%"
end
```

## Working with Anthropic Models

When using Anthropic models, you need to provide images as base64 or raw data:

```ruby
# Configure Anthropic model  
lm = DSPy::LM.new('anthropic/claude-4', api_key: ENV['ANTHROPIC_API_KEY'])

# Load and encode image as base64
File.open('image.jpg', 'rb') do |file|
  image_data = file.read
  base64_data = Base64.strict_encode64(image_data)
  
  image = DSPy::Image.new(
    base64: base64_data,
    content_type: 'image/jpeg'
  )
  
  response = lm.raw_chat do |messages|
    messages.system('You are an image analysis expert.')
    messages.user_with_image('Describe this image in detail.', image)
  end
  
  puts response
end
```

## Working with Google Gemini Models

Google Gemini models are designed with multimodal capabilities from the ground up:

```ruby
# Configure Gemini model
lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'])

# Load and encode image as base64
File.open('product_image.jpg', 'rb') do |file|
  image_data = file.read
  base64_data = Base64.strict_encode64(image_data)
  
  image = DSPy::Image.new(
    base64: base64_data,
    content_type: 'image/jpeg'
  )
  
  response = lm.raw_chat do |messages|
    messages.system('You are a product analysis expert.')
    messages.user_with_image('Analyze this product image for e-commerce listing.', image)
  end
  
  puts response
end
```

### Multiple Images with Gemini

```ruby
# Analyze multiple product angles
images = ['front.jpg', 'back.jpg', 'side.jpg'].map do |filename|
  File.open(filename, 'rb') do |file|
    DSPy::Image.new(
      base64: Base64.strict_encode64(file.read),
      content_type: 'image/jpeg'
    )
  end
end

response = lm.raw_chat do |messages|
  messages.user_with_images(
    'Compare these product images and identify any defects or quality issues.',
    images
  )
end

puts response
```

## Platform Differences

### OpenAI
- **URL Support**: Direct URL references supported
- **Detail Levels**: Can specify `low`, `high`, or `auto` detail
- **Token Costs**: Images consume tokens based on size and detail

### Anthropic
- **Base64 Only**: Images must be base64-encoded or provided as raw data
- **No URL Support**: URLs are not supported directly
- **No Detail Parameter**: The `detail` parameter is not supported
- **Token Costs**: Approximately `(width × height) / 750` tokens

### Google Gemini
- **Base64 Only**: Images must be base64-encoded, URL references not supported
- **No Detail Parameter**: The `detail` parameter is not supported
- **Native Multimodal**: Built for multimodal from the ground up
- **Token Usage**: Tracks token usage in response metadata

## Error Handling

DSPy.rb validates image compatibility with your chosen provider and provides clear error messages:

```ruby
begin
  # Attempt to use vision with non-vision model
  non_vision_lm = DSPy::LM.new('openai/gpt-3.5-turbo', api_key: ENV['OPENAI_API_KEY'])
  image = DSPy::Image.new(url: 'https://example.com/image.jpg')
  
  non_vision_lm.raw_chat do |messages|
    messages.user_with_image('What is this?', image)
  end
rescue ArgumentError => e
  puts "Error: #{e.message}"  # Model does not support vision
end

begin
  # Attempt to use URL with Anthropic (not supported)
  anthropic_lm = DSPy::LM.new('anthropic/claude-4', api_key: ENV['ANTHROPIC_API_KEY'])
  image = DSPy::Image.new(url: 'https://example.com/image.jpg')
  
  anthropic_lm.raw_chat do |messages|
    messages.user_with_image('What is this?', image)
  end
rescue DSPy::LM::IncompatibleImageFeatureError => e
  puts "Error: #{e.message}"  # Anthropic doesn't support image URLs
end

begin
  # Attempt to use URL with Gemini (not supported)
  gemini_lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'])
  image = DSPy::Image.new(url: 'https://example.com/image.jpg')
  
  gemini_lm.raw_chat do |messages|
    messages.user_with_image('What is this?', image)
  end
rescue DSPy::LM::IncompatibleImageFeatureError => e
  puts "Error: #{e.message}"  # Gemini doesn't support image URLs
end
```

## Best Practices

1. **Choose the Right Model**: Use vision-capable models for image tasks
2. **Optimize Image Size**: Resize large images to reduce token usage
3. **Use Appropriate Detail**: Use `low` detail for simple queries, `high` for detailed analysis
4. **Handle Errors Gracefully**: Check for vision support before sending images
5. **Consider Token Costs**: Images can consume significant tokens

## Example: Object Detection

```ruby
# Detect objects in an aerial image
airport_image = DSPy::Image.new(
  url: 'https://example.com/aerial-airport.jpg'
)

response = lm.raw_chat do |messages|
  messages.system(<<~PROMPT)
    You are an object detection system.
    Identify and count all airplanes in the image.
    Provide approximate locations if possible.
  PROMPT
  
  messages.user_with_image('Detect airplanes', airport_image)
end

puts response
```

## Token Usage Considerations

Images consume tokens based on their size:
- **OpenAI**: Varies by model and detail level
- **Anthropic**: Approximately `(width × height) / 750` tokens

Monitor your token usage when working with multiple or large images:

```ruby
response = lm.raw_chat do |messages|
  messages.user_with_image('Describe this', image)
end

puts "Tokens used: #{response.usage.total_tokens}"
```

## Limitations

- **File Types**: Only JPEG, PNG, GIF, and WebP supported
- **Size**: Maximum 5MB per image
- **Medical Images**: Not suitable for medical diagnosis
- **Text Recognition**: May struggle with small or rotated text
- **Spatial Reasoning**: Limited precision for exact measurements

## Examples

Complete working examples are available in the repository:

### Bounding Box Detection
- **File**: [`examples/multimodal/bounding_box_detection.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/multimodal/bounding_box_detection.rb)
- **Features**: Type-safe bounding boxes with `T::Struct`, object detection, normalized coordinates
- **Use Cases**: Aerial image analysis, object counting, computer vision tasks

### Image Analysis  
- **File**: [`examples/multimodal/image_analysis.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/multimodal/image_analysis.rb)
- **Features**: Comprehensive image analysis, color extraction, mood detection, artistic analysis
- **Use Cases**: Art analysis, photography assessment, content moderation, image cataloging

Both examples demonstrate:
- Structured signatures with complex output types
- Type-safe multimodal processing 
- Error handling and provider compatibility
- Integration with different vision models

## Next Steps

- Run the examples locally with your API keys
- Explore custom signature designs for your use cases
- Learn about [complex types](./complex-types.md) for advanced structured outputs
- Check [provider documentation](../production/troubleshooting.md) for model-specific features