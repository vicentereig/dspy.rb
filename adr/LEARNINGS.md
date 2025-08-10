# DSPy.rb Development Learnings

This document captures accumulated knowledge and patterns discovered during DSPy.rb development. These learnings inform best practices and help avoid repeating past mistakes.

## Table of Contents
- [API Design](#api-design)
- [Testing Patterns](#testing-patterns)
- [Type Safety](#type-safety)
- [Provider Integration](#provider-integration)
- [Documentation Management](#documentation-management)
- [Release Process](#release-process)

---

## API Design

### Strategy Configuration Architecture (July 2025)

**Key Learning**: When designing user-facing APIs, prioritize simplicity over exposing internal complexity.

**Problem**: 
- Exposing three internal strategy names (`openai_structured_output`, `anthropic_extraction`, `enhanced_prompting`) created confusion
- Users didn't understand when to use which strategy or why three existed
- String-based configuration was error-prone and not type-safe

**Solution**:
- Created `DSPy::Strategy` enum with two user-facing categories:
  - `DSPy::Strategy::Strict` - Provider-optimized strategies (auto-selects best for current provider)
  - `DSPy::Strategy::Compatible` - Enhanced prompting that works with any provider
- Internal strategy selector maps user preferences to specific implementations
- Automatic fallback from Strict to Compatible when provider features unavailable

**Breaking Change Management**:
- Used minor version bump (0.8.1 → 0.9.0) for breaking API changes
- Provided clear migration instructions in changelog and release notes
- Updated all documentation and tests to use new enum
- Removed backward compatibility to enforce clean migration

### Module-Level LM Configuration (July 2025)

**Key Learning**: Module-level LM configuration uses dry-configurable's `.configure` blocks, not constructor parameters.

**Correct Pattern**:
```ruby
# ✅ CORRECT: Use configure block
@module = DSPy::ChainOfThought.new(SignatureClass)
@module.configure do |config|
  config.lm = DSPy::LM.new('anthropic/claude-3-opus-20240229', api_key: ENV['ANTHROPIC_API_KEY'])
end

# ❌ WRONG: Constructor parameters
@module = DSPy::ChainOfThought.new(
  SignatureClass,
  lm: DSPy::LM.new('anthropic/claude-3-opus-20240229')
)
```

**Important Notes**:
- All DSPy modules inherit from DSPy::Module which includes Dry::Configurable
- The `setting :lm` is defined at the module level for per-instance configuration
- Falls back to global `DSPy.config.lm` if not configured at instance level
- This pattern allows runtime reconfiguration and better testing isolation

---

## Testing Patterns

### Testing Philosophy - API Key Management (August 2025)

**Key Principle**: Tests should FAIL when required environment variables are missing, not skip or use fallbacks.

**Correct Pattern**:
```ruby
# ✅ CORRECT: Test fails if API key missing
it "calls the API", vcr: { cassette_name: "test" } do
  lm = DSPy::LM.new("openai/gpt-4", api_key: ENV['OPENAI_API_KEY'])
  # Test implementation - will fail with clear error if key missing
end

# ✅ CORRECT: Integration test with explicit skip check
it "calls the API", vcr: { cassette_name: "test" } do
  skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
  lm = DSPy::LM.new("openai/gpt-4", api_key: ENV['OPENAI_API_KEY'])
  # test implementation
end
```

**Forbidden Patterns**:
```ruby
# ❌ NEVER: Fallback API keys hide configuration issues
api_key = ENV['OPENAI_API_KEY'] || 'test-key'
lm = DSPy::LM.new("openai/gpt-4", api_key: api_key)

# ❌ NEVER: Create LM before skip check (causes validation errors)
it "calls the API", vcr: { cassette_name: "test" } do
  lm = DSPy::LM.new("openai/gpt-4", api_key: ENV['OPENAI_API_KEY'])
  skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']  # Too late!
end
```

**Rationale**:
- Explicit failures reveal misconfiguration immediately
- VCR cassettes should work with real API calls, not fake keys
- Production code should never have fallback keys
- Clear error messages guide developers to proper setup

### VCR Integration Best Practices (July 2025)

**Key Learning**: Data structures used in VCR recordings need special handling for consistency.

**Best Practices**:
- Normalize all hash keys to symbols before creating response objects
- Use typed structs instead of hashes for data that gets serialized
- Write integration tests that verify features work with VCR playback
- Re-record cassettes periodically to catch provider API changes
- Always re-record cassettes when API responses contain errors
- Verify successful responses (200 OK) in all cassettes

**Testing Strategy Enum Changes**:
- Replace string mocks: `DSPy::Strategy::Compatible` instead of `'enhanced_prompting'`
- Test enum behavior with actual enum values, not serialized strings
- Integration tests need enum updates in multiple spec files
- VCR cassettes unaffected by enum changes (internal strategy names remain same)

---

## Type Safety

### Union Types and Automatic Type Conversion (July 2025)

**Feature Implemented**: DSPy::Prediction now automatically converts LLM JSON responses to proper Ruby types (#42).

**Key Capabilities**:
- **Automatic Hash-to-Struct conversion**: JSON hashes converted to T::Struct instances
- **T::Enum conversion**: String values automatically converted to enum instances
- **Discriminated unions**: Smart type selection based on discriminator fields
- **Nested conversion**: Deep conversion of nested structs and arrays
- **Graceful fallback**: Original hash preserved if conversion fails

**Discriminated Union Pattern**:
```ruby
# ✅ CORRECT: Use T::Enum for discriminators
class ActionType < T::Enum
  enums do
    SpawnTask = new('spawn_task')
    CompleteTask = new('complete_task')
  end
end

output do
  const :action_type, ActionType  # Enum discriminator
  const :details, T.any(SpawnTask, CompleteTask)  # Union type
end

# ❌ AVOID: String discriminators (less type-safe)
output do
  const :action_type, String
  const :details, T.any(SpawnTask, CompleteTask)
end
```

### Token Usage Type Safety with T::Struct (July 2025)

**Problem Solved**: 
- VCR serializes response objects with string keys while live API calls had symbol keys
- Token tracking events weren't being emitted during VCR playback (#48)
- Hash-based usage data was error-prone and inconsistent

**Solution Implemented**:
```ruby
# ✅ CORRECT: Type-safe usage structs
class Usage < T::Struct
  const :input_tokens, Integer
  const :output_tokens, Integer
  const :total_tokens, Integer
end

# Factory handles various formats
usage = UsageFactory.create('openai', usage_data)
```

**Key Insights**:
- Use UsageFactory to normalize various data formats (hash with string keys, symbol keys, API objects)
- OpenAI returns nested objects that need `.to_h` conversion
- T::Struct cannot be subclassed - use separate structs instead of inheritance
- Factory pattern with T.untyped signature supports test doubles

### Sorbet T::Struct Inheritance Limitations and Patterns (January 2025)

**Key Learning**: T::Struct cannot inherit from another T::Struct - this is a deliberate Sorbet limitation for performance optimization.

**The Problem**:
```ruby
# ❌ FORBIDDEN: T::Struct inheritance not allowed
class Response < T::Struct
  const :content, String
  const :usage, Usage
end

class ReasoningResponse < Response  # This will fail!
  const :reasoning_tokens, Integer
end
```

**Why**: Sorbet needs to statically determine all properties of a T::Struct at compile time for performance. It cannot discover properties via inheritance.

**Recommended Pattern - Union Types with Separate Structs**:
```ruby
# ✅ CORRECT: Separate structs with union type
class Response < T::Struct
  const :content, String
  const :usage, Usage
  const :metadata, ResponseMetadata
end

class ReasoningResponse < T::Struct
  const :content, String  # Duplicate fields
  const :usage, Usage
  const :metadata, ResponseMetadata
  const :reasoning_content, T.nilable(String)  # Additional fields
  const :reasoning_tokens, Integer
end

# Type alias for cleaner signatures
ResponseType = T.type_alias { T.any(Response, ReasoningResponse) }

# Usage with type narrowing
def process_response(response)
  case response
  when ReasoningResponse
    # Can access reasoning_content and reasoning_tokens here
    handle_reasoning(response.reasoning_content)
  when Response
    # Regular response handling
    handle_regular(response)
  else
    T.absurd(response)  # Ensures all cases covered
  end
end
```

**Type Narrowing Best Practices**:
```ruby
# Using case statements (preferred)
case response
when ReasoningResponse then process_reasoning(response)
when Response then process_regular(response)
else T.absurd(response)
end

# Using is_a? checks (when needed)
if response.is_a?(ReasoningResponse)
  # Sorbet understands type narrowing here
  puts response.reasoning_tokens
end
```

**Key Takeaways**:
1. Never try to inherit T::Struct from another T::Struct
2. Use union types (T.any) for polymorphic returns
3. Type aliases make signatures cleaner
4. Case statements provide excellent type narrowing
5. Duplication is often better than complex workarounds
6. This limitation exists for Sorbet's performance optimization

### Type Safety with Sorbet Enums

**Best Practices Discovered**:
- Use enum values directly in case statements: `when DSPy::Strategy::Strict`
- Remove `.serialize` and string handling when switching to pure enum approach
- Update type signatures: `params(preference: DSPy::Strategy)` not `T.untyped`
- Enum-based APIs prevent runtime errors and improve IDE support

---

## Provider Integration

### Multimodal Implementation Patterns (January 2025)

**Key Learning**: When adding multimodal support, extend existing message infrastructure rather than creating parallel systems.

**Implementation Approach**:
- Extended `Message` content to accept `T.any(String, T::Array[T::Hash[Symbol, T.untyped]])`
- Reused existing adapter `normalize_messages` with multimodal awareness
- Added provider-specific format conversion methods (`to_openai_format`, `to_anthropic_format`)
- Minimal disruption to existing text-only flows

**Provider Differences**:
- **OpenAI**: Supports direct URL references in `image_url` format
- **Anthropic**: Requires base64-encoded images with `source` blocks
- Model validation through whitelist approach vs. API feature detection

**Message Builder Pattern**:
```ruby
# Single image
message = DSPy::LM::MessageBuilder.user_with_image("What's in this image?", image)

# Multiple images
message = DSPy::LM::MessageBuilder.user_with_images(
  "Compare these images",
  [image1, image2]
)
```

**Testing Multimodal Features**:
- Simple colored squares work better than complex images for integration tests
- Minimal valid PNGs can be constructed programmatically for testing
- VCR cassettes may fail with "unsupported image" if PNG construction is invalid
- Skip integration tests when API keys unavailable rather than mocking

**Design Decisions**:
- No fallback strategies for non-vision models - explicit errors are clearer
- `DSPy::Image` as simple data container, not active record pattern
- Vision model detection via static lists vs. runtime API queries (faster, more reliable)

### Multimodal Support Implementation (August 2025)

**Architecture Design**:
- Created `DSPy::Image` class as central abstraction for image inputs
- Supports three formats: URL (OpenAI only), base64, and byte arrays
- Provider-specific conversions handled transparently

**Provider Differences**:
```ruby
# OpenAI supports direct URLs
image = DSPy::Image.from_url("https://example.com/image.jpg")

# Anthropic requires base64
image = DSPy::Image.from_file("local_image.png")  # Auto-converts to base64
```

**PNG Generation for Tests**:
- Must use proper PNG structure with zlib compression
- Raw binary data will be rejected by APIs
- Created `TestImages` module for reliable test image generation

**Error Handling Philosophy**:
- Surface specific API errors to developers rather than swallowing them
- Provide actionable error messages for common issues (unsupported format, size limits)
- Better developer experience through clear failure reasons

**Provider Compatibility Validation**:
- Added validation at adapter boundary to prevent silent failures
- OpenAI supports: URLs, base64, raw data, detail parameter
- Anthropic supports: base64, raw data only (no URLs or detail)
- Fail-fast approach provides immediate, actionable error messages

```ruby
# Clear error messages guide users to correct usage
"Anthropic doesn't support image URLs. Please provide base64 or raw data instead."
"Anthropic doesn't support the 'detail' parameter. This feature is OpenAI-specific."
```

**Design Pattern Applied**:
- Provider-agnostic core: DSPy::Image remains neutral
- Validation at boundary: Adapters validate before formatting
- Extensible registry: Easy to add new providers and capabilities

### OpenAI API Evolution Insights

**Provider Bug Tracking**:
- OpenAI fixed `additionalProperties` bug that was blocking nested arrays (issue #33)
- API bugs can be temporary - re-record VCR cassettes periodically to verify fixes
- Provider-specific optimization strategies require ongoing maintenance as APIs evolve

**Strategy Selection Philosophy**:
- Provider-optimized approaches (OpenAI structured outputs) are preferred when available
- Enhanced prompting provides reliable fallback for any provider
- User choice between "strict" and "compatible" more intuitive than technical strategy names

---

## Documentation Management

### Documentation Site Management

**Blog Post Layout Issues**:
- Articles in `_articles/` collection must use `layout: blog` not `layout: post`
- Bridgetown collections have specific permalink patterns defined in `bridgetown.config.yml`
- Layout mismatches cause content to render without proper styling/navigation

**Version Synchronization**:
- Always update `Gemfile.lock` when changing gem version in `lib/*/version.rb`
- CI failures due to lockfile mismatches block deployments
- Version references in blog posts and documentation must be updated consistently

**Build Verification Process**:
```bash
# Always verify docs build before pushing changes
cd docs
BRIDGETOWN_ENV=production npm run build
```

### Blog Post Writing Philosophy (July 2025)

**Key Learning**: Focus on benefits and user value rather than generic titles.

**Example**:
- ❌ "The Secret to Cleaner AI Agent Workflows"
- ✅ "Why Union Types Transform AI Agent Development"

**Principles**:
- Lead with the benefit to developers
- Use concrete examples (coffee shop agent demo)
- Show real code patterns users can adopt
- Keep conversational tone without being grandiloquent

### Architecture Decision Records (ADR) (July 2025)

**New Practice**: Created `adr/` directory for documenting significant design decisions.

**Purpose**:
- Record why certain design patterns were chosen
- Document trade-offs and alternatives considered
- Provide context for future maintainers
- Avoid repeating past discussions

**Example**: DSPy::Prediction design decision to use if-else chain for simplicity over complex pattern matching.

---

## Release Process

### Release Process Improvements

**GitHub CLI Integration**:
- Use `gh release create` with `--notes` flag for rich release descriptions
- Include migration examples in release notes for breaking changes
- Link to full changelog for comprehensive change tracking

**Gem Publishing Coordination**:
- Coordinate version updates across: `lib/*/version.rb`, `CHANGELOG.md`, documentation
- Test locally before publishing: `bundle exec rspec` and build verification
- Publish sequence: commit → push → GitHub release → gem push

### Version Management and CI (July 2025)

**Key Learning**: Version bumps require Gemfile.lock updates to keep CI green.

**Process**:
1. Update version in `lib/dspy/version.rb`
2. Run `bundle install` to update Gemfile.lock
3. Commit both files together
4. Push before creating GitHub release

**CI Debugging**:
- Check GitHub Actions logs for specific failure reasons
- Gemfile.lock mismatches are common after version bumps
- Use direct GitHub Actions URLs to investigate failures

---

## User Feedback Insights

**Union Types Request**: "shouldn't next_action be of the type CoordinationActions, like an enum?" - This led to implementing full T::Enum support for discriminators.

This feedback drove the implementation of automatic type conversion for union types and T::Enum support in DSPy::Prediction.