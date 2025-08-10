---
layout: docs
title: Multimodal Support
nav_order: 7
parent: Features
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

## Working with Images

### Creating Images

DSPy.rb provides the `DSPy::Image` class for handling images in various formats:

```ruby
# From URL (OpenAI only)
image = DSPy::Image.new(
  url: 'https://example.com/image.jpg'
)

# From base64 data
image = DSPy::Image.new(
  base64: Base64.strict_encode64(image_data),
  content_type: 'image/jpeg'
)

# From byte array
image = DSPy::Image.new(
  data: image_bytes,
  content_type: 'image/png'
)

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

puts response.content
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

## Advanced: Structured Output with Images

You can combine multimodal inputs with DSPy's structured output capabilities:

```ruby
class ImageAnalysis < DSPy::Signature
  input :instruction, String
  
  output do
    const :description, String
    const :objects, T::Array[String]
    const :dominant_colors, T::Array[String]
    const :mood, String
  end
end

class ImageAnalyzer < DSPy::Predict
  def analyze(image, instruction = "Analyze this image")
    # Note: This is a simplified example
    # In practice, you'd need to handle the multimodal message properly
    forward(instruction: instruction)
  end
end
```

## Platform Differences

### OpenAI
- **URL Support**: Direct URL references supported
- **Detail Levels**: Can specify `low`, `high`, or `auto` detail
- **Token Costs**: Images consume tokens based on size and detail

### Anthropic
- **Base64 Only**: Images must be base64-encoded
- **No URL Support**: URLs must be fetched and converted to base64
- **Token Costs**: Approximately `(width × height) / 750` tokens

## Error Handling

```ruby
begin
  # Attempt to use vision with non-vision model
  non_vision_lm = DSPy::LM.new('openai/gpt-3.5-turbo')
  non_vision_lm.raw_chat do |messages|
    messages.user_with_image('What is this?', image)
  end
rescue ArgumentError => e
  puts "Error: #{e.message}"  # Model does not support vision
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

puts response.content
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

## Next Steps

- Explore the [bounding box detection example](https://github.com/vicentereig/dspy.rb/tree/main/examples/multimodal)
- Learn about [structured outputs](/features/structured-outputs) with images
- Check [provider documentation](/providers) for model-specific features