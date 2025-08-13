---
layout: docs
title: Multimodal Support
nav_order: 7
parent: Core Concepts
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
  input :focus, String, default: 'general', desc: 'Analysis focus'
  input :detail_level, String, default: 'standard', desc: 'Level of detail'
  
  output do
    const :description, String, desc: 'Overall description of the image'
    const :objects, T::Array[String], desc: 'List of objects detected'
    const :dominant_colors, T::Array[String], desc: 'Main colors in the image'
    const :mood, String, desc: 'Overall mood or atmosphere'
    const :style, String, desc: 'Artistic style or characteristics'
    const :lighting, String, desc: 'Description of lighting conditions'
    const :confidence, Float, desc: 'Analysis confidence (0.0-1.0)'
  end
end

class ImageAnalyzer < DSPy::Predict
  def initialize
    super(ImageAnalysis)
  end
  
  def analyze(image, focus: 'general')
    forward(
      focus: focus,
      detail_level: 'detailed'
    )
  end
end

# Usage
analyzer = ImageAnalyzer.new
image = DSPy::Image.new(url: 'https://example.com/landscape.jpg')
result = analyzer.analyze(image, focus: 'colors')

puts result.description
puts "Colors: #{result.dominant_colors.join(', ')}"
puts "Mood: #{result.mood}"
puts "Objects: #{result.objects.join(', ')}"
```

### Object Detection with Type-Safe Bounding Boxes

Use `T::Struct` for type-safe bounding box detection:

```ruby
# Define structured types
class BoundingBox < T::Struct
  const :x, Float, desc: 'Normalized x coordinate (0.0-1.0)'
  const :y, Float, desc: 'Normalized y coordinate (0.0-1.0)'
  const :width, Float, desc: 'Normalized width (0.0-1.0)'
  const :height, Float, desc: 'Normalized height (0.0-1.0)'
end

class DetectedObject < T::Struct
  const :label, String, desc: 'Object type/label'
  const :bbox, BoundingBox, desc: 'Bounding box coordinates'
  const :confidence, Float, desc: 'Detection confidence (0.0-1.0)'
end

class BoundingBoxDetection < DSPy::Signature
  input :query, T.any(String, NilClass), desc: 'Object to detect'
  
  output do
    const :objects, T::Array[DetectedObject], desc: 'Detected objects with bounding boxes'
    const :count, Integer, desc: 'Total number of objects detected'
    const :confidence, Float, desc: 'Overall detection confidence'
  end
end

# Usage with type safety
detector = DSPy::Predict.new(BoundingBoxDetection)
result = detector.call(query: 'airplanes')

result.objects.each do |obj|
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