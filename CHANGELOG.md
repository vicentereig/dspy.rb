# Changelog

All notable changes to DSPy.rb will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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