# Changelog

All notable changes to DSPy.rb will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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