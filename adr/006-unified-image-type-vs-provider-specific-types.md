# ADR-006: Unified Image Type vs. Provider-Specific Types

## Status
Accepted

## Context
With the introduction of comprehensive provider compatibility validation for multimodal images (v0.16.0), a key architectural question emerged: should DSPy use a single unified `DSPy::Image` type with runtime validation, or should we have provider-specific image types for compile-time safety?

### The Problem
Different LLM providers support different image features:
- **OpenAI**: Supports URLs, base64, raw data, and `detail` parameter
- **Anthropic**: Supports base64 and raw data only (no URLs or `detail` parameter)

This creates a design tension between:
1. **Type Safety**: Catching incompatibilities at compile-time
2. **Usability**: Simple, unified API that's easy to learn and use
3. **Flexibility**: Easy to switch providers without major code changes

## Decision
We chose to **keep the unified `DSPy::Image` approach** with runtime validation rather than introducing provider-specific image types.

## Rationale

### Why Unified Approach Wins

#### 1. Simplicity and Usability
```ruby
# ✅ Current approach: Simple and intuitive
image = DSPy::Image.new(url: "https://example.com/image.jpg")
lm.raw_chat { |m| m.user_with_image("What is this?", image) }
# Clear error message if incompatible
```

#### 2. Excellent Runtime Validation
The current validation provides superior developer experience:
```ruby
# Clear, actionable error messages
DSPy::LM::IncompatibleImageFeatureError: 
"Anthropic doesn't support image URLs. Please provide base64 or raw data instead."
```

#### 3. Provider Flexibility  
Easy to switch providers without code changes:
```ruby
# Same image works with different compatible providers
image = DSPy::Image.new(base64: "iVBOR...", content_type: "image/png")

openai_lm.raw_chat { |m| m.user_with_image("Analyze", image) }
anthropic_lm.raw_chat { |m| m.user_with_image("Analyze", image) }
```

#### 4. Future-Proof Architecture
Adding new providers doesn't break existing code:
```ruby
# When Google Gemini Vision support is added, existing images continue working
PROVIDER_CAPABILITIES['google'] = { sources: ['url', 'base64'], parameters: [] }
```

### Problems with Provider-Specific Types

#### 1. Class Explosion and Complexity
```ruby
# ❌ Would need separate classes
DSPy::OpenAI::Image.new(url: "https://...", detail: "high")
DSPy::Anthropic::Image.new(base64: "iVBOR...", content_type: "image/png")
DSPy::Google::Image.new(url: "https://...")
```

#### 2. Conversion Hell
```ruby
# ❌ Complex conversion matrix needed
def analyze_image(lm, image)
  case lm.provider
  when 'openai'
    openai_image = convert_to_openai_image(image)  # How?
  when 'anthropic'  
    anthropic_image = convert_to_anthropic_image(image)  # What if URL?
  end
end
```

#### 3. Generic Code Breakage
```ruby
# ❌ This becomes impossible or very complex
def multi_provider_analysis(images, lms)
  images.zip(lms).each do |image, lm|
    # What if image type doesn't match lm provider?
    result = lm.analyze(image)  # Runtime check anyway?
  end
end
```

#### 4. Tight Coupling
User code becomes tightly coupled to specific providers, reducing flexibility.

#### 5. N×M Complexity Problem
- N providers × M image features = exponential complexity growth
- Every new provider needs conversion logic for every other provider
- Mental model complexity increases dramatically

### Alternatives Considered

#### Option 1: Separate Classes
```ruby
DSPy::OpenAI::Image.new(url: "https://...", detail: "high")
DSPy::Anthropic::Image.new(base64: "...")
```
**Rejected**: Class explosion, conversion complexity

#### Option 2: Factory Pattern  
```ruby
DSPy::Image.for_openai(url: "https://...", detail: "high")
DSPy::Image.for_anthropic(base64: "...")
```
**Rejected**: Still creates provider coupling, harder to switch providers

#### Option 3: Adapter-Specific Builders
```ruby
openai_lm.image(url: "https://...", detail: "high")
anthropic_lm.image(base64: "...")
```
**Rejected**: Inconsistent API, harder to work with generic images

## Implementation Details

### Current Architecture Strengths
1. **Single Concept**: One `DSPy::Image` class to learn
2. **Clear Validation**: Comprehensive provider capability registry
3. **Actionable Errors**: Runtime validation with specific guidance
4. **Extensible Design**: Easy to add new providers and capabilities

### Provider Capability Registry
```ruby
PROVIDER_CAPABILITIES = {
  'openai' => {
    sources: ['url', 'base64', 'data'],
    parameters: ['detail']
  },
  'anthropic' => {
    sources: ['base64', 'data'], 
    parameters: []
  }
}
```

### Validation Architecture
- **Provider-agnostic core**: `DSPy::Image` contains no provider-specific logic
- **Boundary validation**: Adapters validate before formatting API requests
- **Fail-fast approach**: Errors caught before expensive API calls

## Consequences

### Positive
- ✅ Simple mental model: one image type for all providers
- ✅ Excellent developer experience with clear error messages
- ✅ Easy to switch providers without code changes
- ✅ Future-proof: new providers don't break existing code
- ✅ Maintainable: avoid N×M complexity explosion
- ✅ Composable: works well with generic modules and utilities

### Negative
- ❌ Runtime validation instead of compile-time safety
- ❌ Possible confusion about which features work with which providers
- ❌ Image objects may contain unused properties (e.g., `detail` with Anthropic)

### Mitigations
- Comprehensive documentation of provider capabilities
- Excellent error messages guide users to solutions
- Integration tests ensure validation works correctly
- Clear examples in release notes and documentation

## Lessons Learned
1. **Runtime validation with clear errors** can provide better developer experience than complex compile-time safety
2. **Simplicity often trumps theoretical type safety** when the usability benefits are significant  
3. **Provider-agnostic abstractions** are more valuable than provider-specific optimizations
4. **The "hairy factor" is real**: complex architectural choices compound maintenance burden

## Future Considerations
If compile-time safety becomes critical, a hybrid approach could work:
```ruby
# Keep unified interface
image = DSPy::Image.new(url: "https://...")

# Add optional type hints for Sorbet
sig { params(image: DSPy::Image[DSPy::OpenAI]).void }
def openai_specific_processing(image)
  # Sorbet knows this image is OpenAI-compatible
end
```

However, this would still require careful design to avoid the complexity issues identified above.

## References
- [Issue #62: Provider Compatibility Validation](https://github.com/vicentereig/dspy.rb/issues/62)
- [Release v0.16.0: Provider Compatibility Validation](https://github.com/vicentereig/dspy.rb/releases/tag/v0.16.0)
- Implementation files:
  - `lib/dspy/image.rb` - Unified image type with validation
  - `lib/dspy/lm/adapters/` - Provider-specific validation calls
  - `lib/dspy/lm/errors.rb` - IncompatibleImageFeatureError class