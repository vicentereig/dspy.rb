# Changelog

All notable changes to DSPy.rb will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0] - 2025-07-21

### Added
- **Single-Field Union Types with Automatic Type Detection** (#45) - Simplified union type pattern for AI agent development
  - Automatic `_type` field injection in JSON schemas for T::Struct types
  - TypeSerializer automatically adds `_type` field during struct serialization
  - DSPy::Prediction uses `_type` field for automatic type detection in union types
  - No need for manual discriminator fields - just use `T.any()` with structs
  - Supports anonymous structs with fallback to "AnonymousStruct" type name
  - Clean pattern for AI agents that need to choose between different action types

### Examples
- Added coffee-shop-agent example demonstrating single-field union types
  - Shows how to build an AI agent with multiple action types
  - Demonstrates automatic type conversion without discriminator fields
  - Pattern matching on properly typed results

### Documentation
- Updated complex types documentation to reflect new single-field union pattern
- Updated union types blog post to show simplified approach
- Added Architecture Decision Record (ADR-004) for single-field union types design

## [0.10.1] - 2025-07-20

### Added
- **Clear Configuration Error Messages** (#34) - Better error handling when language model is not configured
  - New `DSPy::ConfigurationError` exception with actionable error messages
  - Early validation in instrumentation helpers prevents cryptic nil errors
  - Error messages include examples for both global and module-level configuration
  - Comprehensive test coverage for configuration error scenarios

- **Ruby-OpenAI Gem Conflict Detection** (#29) - Warning system for gem conflicts
  - Detects when community `ruby-openai` gem is loaded alongside DSPy
  - Shows clear warning with migration guidance to official OpenAI SDK
  - Helps prevent namespace conflicts and unexpected behavior
  - Includes detection logic that distinguishes between official and community gems

### Documentation
- Created comprehensive troubleshooting guide covering:
  - Language model configuration errors and solutions
  - Gem conflict resolution steps
  - Common debugging tips and techniques
  - API key configuration examples

### Fixed
- Instrumentation no longer throws `NoMethodError: undefined method 'model' for nil` when LM is not configured
- Module initialization provides clearer feedback when configuration is missing

## [0.10.0] - 2025-07-20

### Added
- **Automatic Hash-to-Struct Type Conversion** (#42) - DSPy::Prediction now automatically converts LLM JSON responses to proper Ruby types
  - Enum values: String responses automatically converted to T::Enum instances
  - Nested structs: Hash responses recursively converted to T::Struct objects
  - Arrays: Elements converted based on their declared types
  - Default values: Missing fields use struct defaults
  - Discriminated unions: Smart type selection based on discriminator fields (String or T::Enum)
  - Graceful fallback: Original hash preserved if conversion fails

### Features
- **Union Type Support with T.any()** - Clean handling of multiple possible types
  - Automatic struct selection for discriminated unions
  - Support for T::Enum discriminators (recommended pattern)
  - Array elements with union types converted correctly
  - Deep nesting support (3+ levels with performance considerations)

### Documentation
- Added comprehensive "Automatic Type Conversion" section to complex types documentation
- Updated signatures documentation to highlight automatic conversion feature
- Created blog post "Union Types: The Secret to Cleaner AI Agent Workflows" demonstrating the pattern
- Established Architecture Decision Records (ADR) directory for design decisions

### Infrastructure
- Fixed GitHub Actions to generate OG images in production builds (GENERATE_OG_IMAGES=true)
- Added comprehensive edge case tests for DSPy::Prediction type conversion

### Fixed
- Unicode characters now display correctly in Example#to_s output (e.g., "÷" instead of "\u00F7")

## [0.9.1] - 2025-07-16

### Fixed
- **ReAct Agent Input Flexibility** (#41) - Fixed bug where ReAct agents failed with non-string first inputs or array inputs
  - Removed hardcoded assumption that first input field is always a String "question"
  - ReAct now serializes all input fields as JSON and passes as `input_context` to LLM
  - Supports array inputs, non-string first inputs, and signatures with no string fields
  - Updated internal signatures to use generic `input_context` instead of specific `question` field
  - Added comprehensive integration tests for edge cases

### Added
- **Enhanced ReAct Input Handling** - ReAct agents now work with any input signature structure
  - Array inputs: `const :tasks, T::Array[Task]`
  - Non-string first inputs: `const :number, Integer`
  - Complex nested structures and arbitrary field combinations
  - Maintains backward compatibility with existing ReAct agents

### Documentation
- Verified documentation already correctly showed ReAct flexibility
- No documentation updates needed - implementation now matches documented behavior

## [0.9.0] - 2025-07-11

### Breaking Changes
- **Strategy Configuration API** - Simplified strategy configuration using type-safe enums
  - Replaced complex strategy name strings with `DSPy::Strategy::Strict` and `DSPy::Strategy::Compatible` enum values
  - `DSPy::Strategy::Strict` selects provider-optimized strategies (OpenAI structured outputs, Anthropic extraction)
  - `DSPy::Strategy::Compatible` uses enhanced prompting that works with any provider
  - **BREAKING**: String strategy names like `"enhanced_prompting"` are no longer supported
  - **Migration**: Replace `config.structured_outputs.strategy = "enhanced_prompting"` with `config.structured_outputs.strategy = DSPy::Strategy::Compatible`

### Added
- **User-Friendly Strategy Categories** - Two clear strategy options instead of three internal implementations
  - Automatic fallback from Strict to Compatible when provider-specific features are unavailable
  - Type-safe enum values with Sorbet integration
  - Clearer documentation and error messages

### Documentation
- Updated all documentation to use new enum-based strategy configuration
- Improved blog post with correct version references and enum examples
- Clarified strategy selection behavior and fallback logic

## [0.8.1] - 2025-07-11

### Fixed
- **OpenAI Structured Outputs with Nested Arrays** (#33) - Re-enabled test for nested arrays after OpenAI fixed API bug
  - OpenAI API now correctly handles `additionalProperties` for nested arrays of primitive types
  - Re-recorded VCR cassette showing successful API response for complex nested structures
  - Restored original `tags: T::Array[String]` field in test cases
- **Test Infrastructure Improvements** - Fixed class naming conflicts in test adapters

### Added
- **Comprehensive Edge Case Testing** - Added extensive test coverage for OpenAI structured outputs
  - Deeply nested objects (5+ levels) with depth validation warnings
  - Mixed required/optional fields with `T.nilable` support
  - Arrays with varying object complexity
  - Schema depth validation and compatibility checks

### Documentation
- Updated issue #33 with findings showing OpenAI API bug resolution
- Enhanced test coverage for structured output edge cases

## [0.8.0] - 2025-07-11

### Added
- **JSON Parsing Reliability Features** (#18) - Comprehensive improvements for reliable JSON extraction from LLMs
  - **OpenAI Structured Outputs** - Native support for OpenAI's JSON schema mode with guaranteed valid JSON
  - **Automatic Strategy Selection** - Provider-optimized extraction (OpenAI structured outputs, Anthropic patterns, enhanced prompting)
  - **Smart Retry Logic** - Progressive fallback with exponential backoff for handling transient failures
  - **Performance Caching** - Schema and capability caching for faster repeated operations
- **Enhanced Error Recovery** - Retry mechanisms with strategy fallback for maximum reliability
- **Improved Error Messages** - Detailed JSON parsing errors with content length and context

### Changed
- LM adapters now support provider-specific optimizations for JSON extraction
- Configuration system extended with structured output settings

### Documentation
- Added JSON extraction strategies documentation
- Added reliability features documentation
- Created blog post on JSON parsing reliability improvements
- Updated README with new production features

## [0.7.0] - 2025-01-11

### Added
- **Default Values for Signatures** (#32) - Input and output fields can now have default values, reducing boilerplate and handling missing LLM responses gracefully
- **API Key Validation** (#27) - Immediate validation at initialization with helpful error messages including environment variable names
- **CodeAct Module Documentation** - Comprehensive documentation for the dynamic code generation module unique to DSPy.rb
- **Ruby-Idiomatic Examples** - Added Ruby-style examples throughout documentation showcasing collections, blocks, and method chaining
- **Blog Section** - New blog section with posts on Ruby-idiomatic APIs, CodeAct deep dive, and ReAct tutorial
- **Rails Integration Guide** (#30) - Comprehensive documentation for Rails developers including enum handling, service objects, and ActiveJob patterns

### Changed
- Improved error messages for missing API keys to include provider-specific environment variable names
- Enhanced documentation structure with clearer navigation and more examples

### Fixed
- Default values now properly work with T::Struct for both input and output fields
- API key validation prevents runtime errors from nil or empty keys
- Documentation clarified around Rails enum handling to resolve confusion

### Documentation
- Added comprehensive CodeAct module documentation with safety considerations
- Created Rails integration guide with enum handling examples
- Added "Default Values" section to signatures documentation
- Created three blog posts: Ruby-idiomatic APIs, CodeAct deep dive, and ReAct tutorial
- Enhanced quick start guide with Ruby-style examples

## [0.6.4] - Previous releases...