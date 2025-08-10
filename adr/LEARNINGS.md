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
  config.lm = DSPy::LM.new('openai/gpt-4')
end

# ❌ WRONG: Constructor parameters
@module = DSPy::ChainOfThought.new(SignatureClass, lm: lm)
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

### Sorbet T::Struct Inheritance Limitations (January 2025)

**Key Learning**: T::Struct cannot inherit from another T::Struct - Sorbet limitation for performance.

**The Problem**: Inheritance between T::Structs is forbidden.

**Solution**: Use separate structs with union types:
```ruby
# Separate structs
class Response < T::Struct
  const :content, String
  const :usage, Usage
end

class ReasoningResponse < T::Struct
  const :content, String  # Duplicate fields when needed
  const :usage, Usage
  const :reasoning_tokens, Integer  # Additional fields
end

# Type alias for polymorphism
ResponseType = T.type_alias { T.any(Response, ReasoningResponse) }

# Type narrowing with case
case response
when ReasoningResponse then handle_reasoning(response)
when Response then handle_regular(response)
else T.absurd(response)
end
```

**Key Takeaways**: Use union types for polymorphism, duplication is OK, case statements for type narrowing.

### Type Safety with Sorbet Enums

**Best Practices Discovered**:
- Use enum values directly in case statements: `when DSPy::Strategy::Strict`
- Remove `.serialize` and string handling when switching to pure enum approach
- Update type signatures: `params(preference: DSPy::Strategy)` not `T.untyped`
- Enum-based APIs prevent runtime errors and improve IDE support

---

## Provider Integration

### Multimodal Implementation (January 2025)

**Key Learning**: Extend existing message infrastructure rather than creating parallel systems.

**Implementation**:
- Extended `Message` content to accept multimodal arrays
- Created `DSPy::Image` class as central abstraction
- Provider-specific conversions handled transparently

**Provider Differences**:
- **OpenAI**: Supports direct URLs, base64, raw data, detail parameter
- **Anthropic**: Base64/raw data only (no URLs or detail parameter)

**Message Builder Pattern**:
```ruby
# Simple API for single or multiple images
message = DSPy::LM::MessageBuilder.user_with_image("What's this?", image)
message = DSPy::LM::MessageBuilder.user_with_images("Compare", [img1, img2])
```

**Design Principles**:
- Provider-agnostic core with validation at adapter boundary
- Explicit errors over silent fallbacks
- Static model lists over runtime API detection


### OpenAI API Evolution Insights

**Provider Bug Tracking**:
- OpenAI fixed `additionalProperties` bug that was blocking nested arrays
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

**Union Types Request**: Led to implementing full T::Enum support for discriminators and automatic type conversion in DSPy::Prediction.