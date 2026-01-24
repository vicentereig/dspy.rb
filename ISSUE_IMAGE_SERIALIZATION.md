# Bug: DSPy::Image in signature inputs gets serialized as Ruby object string

## Summary

When using `DSPy::Image` as an input field in a signature, the image is serialized as its Ruby object string (`#<DSPy::Image:0x...>`) instead of being properly formatted for the LLM API. The LLM receives the literal string instead of actual image data.

## Reproduction

```ruby
class BookPageOcr < DSPy::Signature
  description "Extract text from a scanned book page"

  input do
    const :image, DSPy::Image, description: "The scanned page image"
    const :page_number, Integer
  end

  output do
    const :text_content, String
  end
end

# This fails - LLM sees "#<DSPy::Image:0x...>" instead of image data
predictor = DSPy::Predict.new(BookPageOcr)
image = DSPy::Image.new(data: File.binread("page.png"), content_type: "image/png")
result = predictor.call(image: image, page_number: 1)

# LLM response: "Unable to process page. The image reference #<DSPy::Image:0x...>
# is a Ruby object reference rather than an actual image file..."
```

## Root Cause

The issue is in `LM#build_messages` (`lib/dspy/lm.rb:144-172`):

```ruby
def build_messages(inference_module, input_values)
  # ...
  user_prompt = prompt.render_user_prompt(input_values)  # ← Images serialized here
  messages << Message.new(
    role: Message::Role::User,
    content: user_prompt  # ← Plain string, not multimodal content
  )
end
```

The call chain:
1. `Prompt#render_user_prompt(input_values)` calls `serialize_for_json(input_values)`
2. `serialize_for_json` handles `T::Struct`, `Hash`, `Array`, `T::Enum` but NOT `DSPy::Image`
3. `DSPy::Image` falls through to the `else` branch which returns it as-is
4. `JSON.pretty_generate` calls `to_s` on the image → `"#<DSPy::Image:0x...>"`

## Expected Behavior

The documentation at `docs/src/core-concepts/multimodal.md` shows signatures with `DSPy::Image` inputs should work:

```ruby
class ImageAnalysis < DSPy::Signature
  input do
    const :image, DSPy::Image, description: 'Image to analyze'
  end
  # ...
end

analyzer = DSPy::Predict.new(ImageAnalysis)
result = analyzer.call(image: image)  # Should work!
```

## Proposed Solutions

### Option 1: Handle images in `LM#build_messages` (Recommended)

Detect images in input values and build multimodal messages:

```ruby
def build_messages(inference_module, input_values)
  messages = []
  prompt = get_prompt(inference_module)

  system_prompt = prompt.render_system_prompt
  messages << Message.new(role: Message::Role::System, content: system_prompt) if system_prompt

  # Extract images from input values
  images = extract_images_from_input(input_values)
  text_inputs = input_values.reject { |_, v| v.is_a?(DSPy::Image) }
  user_prompt = prompt.render_user_prompt(text_inputs)

  if images.any?
    # Build multimodal content array
    content = [{ type: 'text', text: user_prompt }]
    images.each { |img| content << { type: 'image', image: img } }
    messages << Message.new(role: Message::Role::User, content: content)
  else
    messages << Message.new(role: Message::Role::User, content: user_prompt)
  end

  messages
end

def extract_images_from_input(input_values)
  input_values.values.select { |v| v.is_a?(DSPy::Image) }
end
```

### Option 2: Handle in `Prompt#serialize_for_json`

Add special handling for `DSPy::Image` to return a placeholder that can be post-processed:

```ruby
def serialize_for_json(obj)
  case obj
  when DSPy::Image
    { _dspy_image_ref: obj.object_id }  # Placeholder for later substitution
  # ... existing cases
  end
end
```

Then post-process in `build_messages` to replace placeholders with actual multimodal content.

### Option 3: Validate and error early

If multimodal signatures aren't fully supported yet, add validation to prevent silent failures:

```ruby
def validate_input_struct(input_values)
  input_values.each do |key, value|
    if value.is_a?(DSPy::Image)
      raise ArgumentError, "DSPy::Image inputs in signatures are not yet supported. Use lm.raw_chat with user_with_image instead."
    end
  end
  # ... existing validation
end
```

## Impact

This affects any signature that uses `DSPy::Image` as an input type. The multimodal integration tests pass because they use `raw_chat` with `user_with_image`, not `Predict` with signatures.

## Environment

- DSPy.rb version: 0.34.2
- dspy-anthropic version: 1.0.1
- Ruby version: 3.3.x

## Related

- Multimodal documentation: `docs/src/core-concepts/multimodal.md`
- MessageBuilder multimodal methods: `lib/dspy/lm/message_builder.rb:44-70`
- Adapter multimodal handling: `lib/dspy/lm/adapter.rb:54-59`
