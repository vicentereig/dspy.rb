# Changelog

All notable changes to DSPy.rb will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.27.2] - 2025-09-16

### Added
- **Comprehensive Sorbet Type Support for Tools and Toolsets** - Complete type parity with Signatures (resolves #113)
  - Automatic JSON-to-Ruby type conversion for all Sorbet types in tool parameters
  - Full T::Enum support with string-to-enum conversion (e.g., `"add"` → `Operation::Add`)
  - T::Struct support with recursive hash-to-struct conversion for complex nested data
  - T::Array and T::Hash support with proper element and value type coercion
  - T.nilable and T.any (union) type handling with automatic type resolution
  - Consistent JSON schema generation across Tools, Toolsets, and Signatures
  - Enhanced LLM template documentation with comprehensive typed tooling examples

### Fixed
- **Test Infrastructure Improvements** - Enhanced reliability and consistency
  - Updated test schema structure to use function wrapper format for LLM tool compatibility
  - Resolved enum scoping issues in type consistency tests
  - Fixed memory toolset tests to properly handle nilable array types
  - Corrected documentation inaccuracies in observability guide
  - Resolved test isolation issues in Gemini schema converter

### Improved
- **Developer Experience Enhancements**
  - Enhanced type coercion system with comprehensive error handling
  - Unified type system module for consistent behavior across all components
  - Improved LLM guidance documentation emphasizing type-safe tool creation
  - Better automatic type conversion examples and real-world usage patterns

### Technical Details
- Implemented `DSPy::TypeSystem::SorbetJsonSchema` module for unified type conversion
- Enhanced `DSPy::Mixins::TypeCoercion` with comprehensive Sorbet type support
- Updated Tools::Base and Tools::Toolset to use unified type system architecture
- Full backward compatibility maintained with existing tool implementations

## [0.27.0] - 2025-09-13

### Added
- **Native Gemini Structured Outputs** - Comprehensive support for Google Gemini AI structured generation
  - Uses Gemini's controlled generation with `response_mime_type: "application/json"` and `response_schema`
  - High-priority strategy (priority 100) for optimal selection with Gemini models
  - Full support for `gemini-1.5-pro` and `gemini-1.5-flash` models
  - Automatic schema conversion from DSPy signatures to OpenAPI 3.0 format
  - Seamless fallback to EnhancedPromptingStrategy for unsupported models
  - Zero breaking changes with optional `structured_outputs: true` parameter

### Improved
- **Type Safety Enhancements** - Better code maintainability and reliability
  - Refactored StrategySelector to use T::Enum for type-safe strategy names
  - Enhanced unit test isolation for schema converter
  - Added comprehensive integration test suite with VCR cassettes

### Fixed
- **Test Infrastructure** - Improved reliability and isolation
  - Fixed unit test isolation issues in schema converter
  - Updated VCR cassettes with proper SSEVCR format
  - Enhanced evaluation test expectations for validation set length

### Documentation
- Added comprehensive documentation for Gemini structured outputs usage
- Updated troubleshooting guide with Gemini-specific information
- Enhanced JSON extraction documentation with Gemini examples

### Technical Details
- Implemented `DSPy::LM::Adapters::Gemini::SchemaConverter` for OpenAPI 3.0 schema generation
- Added `DSPy::LM::Strategies::GeminiStructuredOutputStrategy` with provider-optimized selection
- Full test coverage: 24 new unit tests and integration test suite
- Performance optimized with schema caching and priority ordering

## [0.26.1] - 2025-09-10

### Changed
- **MIPROv2 Configuration Modernization** - Ruby-idiomatic configuration pattern
  - Replaced `MIPROv2Config` class with dry-configurable blocks
  - Class-level and instance-level configuration support
  - Type-safe optimization strategies using T::Enum symbols
  - Simplified data structures with `EvaluatedCandidate` Data class

### Breaking Changes
- **REMOVED**: `MIPROv2Config` class - Use `DSPy::Teleprompt::MIPROv2.configure` blocks
- **CHANGED**: optimization_strategy values - Use symbols (`:greedy`) instead of strings
- **RENAMED**: `CandidateConfig` → `EvaluatedCandidate` - Now a simple Data class

### Improved
- Enhanced test coverage for configuration patterns
- Fixed test state isolation issues
- Better error messages and validation
- Updated documentation with new configuration patterns

## [0.26.0] - 2025-01-09

### Added
- **Real Bayesian Optimization in MIPROv2** - State-of-the-art prompt optimization with Gaussian Processes
  - Pure Ruby implementation with zero external dependencies (no LAPACK/OpenBLAS required)
  - Upper Confidence Bound (UCB) acquisition function for intelligent exploration/exploitation
  - Graceful fallbacks to adaptive selection when GP fails or insufficient data
  - Comprehensive test coverage for Bayesian optimization behavior

### Changed
- **MIPROv2 API Refactoring** - Cleaner, more Ruby-idiomatic configuration
  - Replaced constructor parameters with dry-configurable pattern
  - Added T::Enum types for CandidateType and OptimizationStrategy
  - Enable idiomatic Ruby configuration: `candidate.configure { |c| c.instruction = '...' }`
  - Updated all documentation with new API patterns

### Improved
- **Dependency Optimization** - Lighter, faster installation
  - Replaced unused polars-df dependency with lightweight numo-narray
  - Resolved dependency conflicts and simplified setup
  - Zero-dependency installation removes complex system requirements

### Technical Details
- Implemented pure Ruby Gaussian Process in `DSPy::Optimizers::GaussianProcess`
- Added sophisticated kernel functions and matrix operations without external libraries
- Enhanced MIPROv2 with three optimization strategies: greedy, adaptive, and Bayesian
- Full backward compatibility maintained with existing MIPROv2 usage

## [0.25.1] - 2025-09-08

### Changed
- **Telemetry Export Interval** - Aligned with New Relic's 60-second harvest cycle
  - Changed default export interval from 1 second to 60 seconds
  - Reduces network overhead by 60x while maintaining observability
  - Matches industry-standard monitoring agent patterns

### Added
- **Production Trade-offs Documentation** - Comprehensive architecture documentation
  - Documents memory protection through queue limits (1000 spans)
  - Explains FIFO span dropping under extreme load
  - Acknowledges acceptable sample loss prioritizing application stability
  - Aligns with New Relic and other production monitoring approaches

### Technical Details
- `DEFAULT_EXPORT_INTERVAL` changed from 1.0 to 60.0 seconds in AsyncSpanProcessor
- Updated architectural documentation with industry comparisons
- Maintains backward compatibility via `DSPY_TELEMETRY_EXPORT_INTERVAL` env var

## [0.25.0] - 2025-09-07

### Added
- **Async Telemetry System** - Non-blocking observability with background export
- **Complete GEPA Optimization** - Genetic algorithm implementation for program optimization
- **GPT-5 Support** - Support for latest OpenAI model
- **ReflectionEngine** - LLM-based analysis and reflection capabilities

### Fixed
- OpenTelemetry/Langfuse span reporting and timing consistency
- ChainOfThought 0.00s duration issue in span observations
- GEPA implementation with proper test coverage and examples
- Local embedding batch processing with informers gem

### Changed
- Eliminated simple_mode from GEPA - always use full optimization
- Improved test performance and VCR recording speed
- Enhanced OpenTelemetry span timing and operation naming

## [0.24.2] - 2025-09-05

### Fixed
- Langfuse timing fixes and stability improvements

## [0.24.1] - 2025-09-05

### Fixed
- Enhanced Langfuse integration and bug fixes

## [0.24.0] - 2025-09-05

### Added
- GEPA optimization fixes and improvements

## [0.23.0] - 2025-09-05

### Added
- GEPA Optimizer implementation

## [0.22.1] - 2025-09-05

### Fixed
- **Type Coercion Bug** - Direct T::Struct fields now properly handle `_type` discriminator filtering (by [@liorbrauer](https://github.com/liorbrauer))
  - Previously only union types (T.any) correctly filtered out DSPy's internal `_type` field
  - Direct struct fields would fail with "Can't set field to {\"_type\"=>...}" errors
  - Added recursive type coercion for nested structs at any depth
  - Smart filtering preserves legitimate user-defined `_type` fields

### Documentation
- **Type Discriminator Pattern** - Comprehensive documentation of DSPy's `_type` field handling
  - Explains automatic discriminator field injection for JSON schemas
  - Documents reserved `_type` field name and filtering behavior
  - Shows real JSON schema structure with `oneOf` and `const` constraints
  - Covers both union types and direct struct fields

### Technical Details
- Enhanced `coerce_struct_value` method to match `coerce_union_value` behavior
- Added 15+ comprehensive tests covering direct struct coercion scenarios
- Maintains backward compatibility - no breaking changes

## [0.22.0] - 2025-09-04

### Added
- **GEPA (Generalized Event Pattern Analysis) Phase 1** - Advanced telemetry and event processing system
  - TraceCollector for comprehensive application monitoring
  - ReflectionEngine for runtime behavior analysis
  - Event-driven architecture for LLM application insights
  - Integration with OpenTelemetry for production observability

### Enhanced
- **Telemetry System** - Improved OpenTelemetry span attribute serialization
  - Configuration hash properly serialized to JSON format
  - Better structured logging for debugging and monitoring
  - Enhanced span tracking for complex LLM workflows

### Contributors
This release features contributions from:
- [@liorbrauer](https://github.com/liorbrauer) (Lior Brauer) - Critical type coercion bug fix

### Technical Details
- GEPA Phase 1 provides foundation for advanced LLM application analytics
- Event system enables real-time monitoring and optimization
- Structured telemetry data improves production debugging capabilities

## [0.21.0] - 2025-09-01

### Added
- **Comprehensive Type Alias Support** - DSPy.rb now fully supports Sorbet type aliases (T.type_alias)
  - Added type alias detection and resolution in signature.rb for proper JSON schema generation
  - Enhanced T::Types::FixedHash handling with specific properties and required fields
  - Improved example generation in enhanced prompting strategy with recursive generate_example_value method
  - Proper handling of nested objects, arrays, and union types in type alias examples
  - LLMs now receive structured JSON schemas with realistic examples instead of generic "example value" placeholders
  - Enables developers to use type aliases for structured responses while maintaining proper LLM communication

### Enhanced
- **Documentation Clarity** - Improved attribution and relationship clarity with Stanford DSPy
  - Updated README.md to explicitly state DSPy.rb is an "idiomatic Ruby port" of Stanford's DSPy framework
  - Added Stanford attribution to documentation homepage
  - Clarified Ruby-specific innovations and enhancements

### Contributors
This release features a major contribution from:
- **[@TheDumbTechGuy](https://github.com/TheDumbTechGuy)** (Stefan Froelich) - Complete type alias support implementation with comprehensive test coverage

### Technical Details
- Type aliases (T.type_alias) are now properly resolved to their underlying T::Types::FixedHash structures
- Enhanced prompting strategy generates proper examples for complex nested structures
- Added 9 new comprehensive tests covering schema generation and example generation scenarios
- Maintains backward compatibility with existing DSPy.rb applications

## [0.20.1] - 2025-08-27

### Fixed
- Corrected canonical URLs for 16 blog articles for proper SEO
- Fixed article layout configuration from 'article' to 'blog'
- Removed non-existent Gemini models from vision_models.rb
- Corrected misleading raw_chat API documentation

### Documentation
- Added v0.20.0 release announcement blog post
- Various documentation improvements and edits

## [0.20.0] - 2025-08-26

### Added
- **Google Gemini API Integration** (by [@TheDumbTechGuy](https://github.com/TheDumbTechGuy))
  - Complete support for Google's Gemini models (`gemini-1.5-flash`, `gemini-1.5-pro`, `gemini-1.0-pro`)
  - Dual client architecture with streaming and non-streaming support
  - Comprehensive error handling with Gemini-specific error messages
  - Token usage tracking and response metadata for cost monitoring
  - Multimodal image support with base64 encoding (URLs not supported)
  - Provider compatibility validation with clear error messages
  - Integration with DSPy's instrumentation and observability system

- **Fiber-Local LM Context Management** (by [@TheDumbTechGuy](https://github.com/TheDumbTechGuy))  
  - New `DSPy.with_lm` method for temporary language model overrides
  - Uses Ruby's fiber-local storage for clean, thread-safe context management
  - Supports nested contexts with automatic cleanup on exceptions
  - Enables concurrent LM usage patterns without complex configuration
  - Clear hierarchy: instance-level > fiber-local > global LM resolution
  - Perfect for A/B testing, environment switching, and privacy-sensitive processing

- **Program Serialization and Persistence** (by [@TheDumbTechGuy](https://github.com/TheDumbTechGuy))
  - Implemented `from_h` method for restoring saved programs from serialized data
  - Complete program state preservation including instructions, examples, and configuration
  - Enhanced `ProgramStorage` with better error handling and metadata tracking
  - Version compatibility tracking with DSPy and Ruby version information
  - Support for program import/export across environments
  - Automatic state extraction and reconstruction for all module types

- **Documentation and Community**
  - **CONTRIBUTORS.md** - New contributor recognition file highlighting Stefan Froelich's major contributions
  - **Google Gemini Provider Documentation** - Comprehensive guide with examples and best practices
  - **Fiber-Local LM Context Guide** - Detailed documentation with use cases and patterns
  - **Program Persistence Guide** - Complete documentation for saving and loading optimized programs
  - Updated multimodal documentation with Gemini provider information
  - Updated installation guide to reflect gem availability

### Enhanced
- **MIPROv2 Optimizer Improvements** (by [@TheDumbTechGuy](https://github.com/TheDumbTechGuy))
  - Fixed critical bootstrap phase hanging issue that could cause infinite loops
  - Added metric parameter support to AutoMode factories for flexible optimization
  - Improved optimization trace serialization for JSON output and debugging
  - Better error handling and recovery during optimization phases
  - Enhanced observability events for optimization tracking

### Fixed
- **CodeAct and ReAct Signature Name Tracking** - Fixed agent signature name tracking in observability
- **Grounded Proposer Enum Value Extraction** - Improved enum value extraction for instruction generation
- **Observability Code Cleanup** - Refined event emission and instrumentation accuracy

### Documentation
- Enhanced OG meta tags support for better social media sharing
- Modernized README with current shields.io badges
- Updated installation instructions to remove pre-release warnings
- Comprehensive provider comparison matrix (OpenAI vs Anthropic vs Gemini)
- New evaluation framework blog article
- Updated multimodal examples with type-safe struct demonstrations

### Contributors
This release features significant contributions from:
- **[@TheDumbTechGuy](https://github.com/TheDumbTechGuy)** (Stefan Froelich) - 9 transformational commits including Gemini integration, fiber-local contexts, program persistence, and MIPROv2 improvements
- **[@vicentereig](https://github.com/vicentereig)** - 16 commits for documentation, multimodal features, and site improvements

### Roadmap Progress
This release advances key roadmap priorities:
- ✅ **Provider Expansion** - Added Google Gemini support
- ✅ **Better Context Management** - Fiber-local LM contexts  
- ✅ **Improved Persistence** - Program serialization system
- ✅ **Optimizer Reliability** - MIPROv2 stability fixes

### Breaking Changes
None - this release maintains full backward compatibility with existing DSPy.rb applications.

### Migration Notes
- Gemini models require base64-encoded images (no URL support)
- Program serialization requires implementing `from_h` for custom modules
- New fiber-local LM contexts provide cleaner patterns than manual model passing

## [0.18.1] - 2025-08-10

### Fixed
- **ChainOfThought Signature Name Tracking** - Fixed `dspy.signature=nil` in observability logs
  - Enhanced signature classes created by ChainOfThought now preserve the original signature name
  - Properly tracks signature names in span tracking and reasoning analysis events
  - Fixes issue where logging showed `dspy.signature=nil` instead of actual signature name (e.g., `MathProblemSolver`)
  - Added comprehensive test coverage for signature name preservation

## [0.18.0] - 2025-08-10

### Added
- **Plausible Analytics Integration** - Enhanced tracking capabilities for web analytics
  - Added new event types and improved tracking structure
  - Better support for custom properties and event metadata
  - Improved error handling and retry logic

## [0.17.0] - 2025-01-08

### Changed
- **Upgraded Anthropic SDK** - Updated from `~> 1.1.1` to `~> 1.5.0`
  - Includes Search Result Content Blocks API support
  - AWS Bedrock base URL compatibility fixes  
  - Performance improvements and bug fixes
  - All existing functionality remains compatible
  - Foundation for future reasoning model integration

## [0.15.7] - 2025-08-07

### Changed
- **Updated SDK Dependencies** - Updated to latest stable versions of official SDKs
  - OpenAI SDK updated from `~> 0.13.0` to `~> 0.16.0`
  - Anthropic SDK updated from `~> 1.1.0` to `~> 1.1.1`
  - Both updates maintain backward compatibility with existing code
  - Enables access to latest features: OpenAI structured outputs improvements, webhook verification
  - All tests pass with updated SDKs

## [0.15.6] - 2025-08-05

### Fixed
- **Union Type Resilience Against LLM Hallucinations** (#59) - Fixed type coercion to filter extra fields not defined in structs
  - When LLMs return extra fields that aren't part of the target T::Struct, these are now automatically filtered out
  - Prevents `ArgumentError: Unrecognized properties` when LLMs confuse similar concepts or add hallucinated fields
  - Example: If LLM returns `synthesis` field for `ReflectAction` (which only has `reasoning` and `thoughts`), it's silently ignored
  - Makes DSPy.rb agents more robust to prompt changes and model variations
  - Added comprehensive test coverage and updated documentation

## [0.15.5] - 2025-08-03

### Fixed
- **Nilable Arrays with Union Types** (#56) - Fixed type conversion for nilable arrays containing union types
  - `T.nilable(T::Array[T.any(StructA, StructB)])` now properly converts array elements to struct instances
  - Previously elements remained as hashes instead of being converted to their respective types
  - Updated `needs_array_conversion?` and `convert_array_elements` to handle nilable wrapper types
  - Added comprehensive test coverage for nilable array edge cases

## [0.15.4] - 2025-08-02

### Fixed
- **Enum Coercion in Union Types** - Fixed edge case where enum fields within union types weren't properly coerced
  - Union type conversion now recursively applies type coercion to all struct fields
  - Fixes coffee shop example where `DrinkSize` enum was passed as string from LLM
  - Added comprehensive test coverage for enum fields within union types
  - Example: `T.any(MakeDrink, RefundOrder)` with `size: DrinkSize` enum field now works correctly

## [0.15.3] - 2025-08-02

### Fixed
- **Union Type Conversion in Predictors** (#54) - Fixed automatic conversion of LLM responses to union types
  - Added union type handling to `TypeCoercion` mixin used by `DSPy::Predict` and `DSPy::ChainOfThought`
  - LLM responses with `_type` discriminators are now correctly converted to appropriate struct instances
  - Enables elegant union type patterns in predictors as documented
  - Example: `T.any(SearchAction, AnswerAction)` now works correctly with predictors

## [0.15.2] - 2025-07-28

### Fixed
- **CI Test Failures** - Resolved test failures in continuous integration
  - Fixed class name collision between CodeAct and Ollama integration tests
  - Re-recorded VCR cassettes to match updated TypeSerializer request format
  - Renamed `MathProblem` to `CodeActMathProblem` in CodeAct specs to avoid conflicts

## [0.15.1] - 2025-07-28

### Fixed
- **CodeAct Input Flexibility** - Fixed CodeAct to handle any input signature structure
  - Removed hardcoded assumption about input fields (similar to ReAct fix in v0.9.1)
  - Now uses `TypeSerializer.serialize` to properly handle all input types
  - Supports array inputs, non-string fields, and complex signatures
  - Maintains backward compatibility with existing CodeAct agents

### Documentation
- Fixed Ollama blog post frontmatter to use `description` instead of `summary` for proper display

## [0.15.0] - 2025-07-28

### Added
- **Ollama Support** - Run LLMs locally with full DSPy.rb functionality
  - New `OllamaAdapter` using Ollama's OpenAI-compatible API
  - Support for both local (default) and remote Ollama instances
  - Optional API key authentication for remote instances
  - Structured output support with automatic fallback strategies
  - Full token usage tracking and instrumentation
  - Comprehensive integration tests with VCR recordings

### Documentation
- Updated installation guide with Ollama setup instructions
- Added Ollama examples to quick start guide
- Updated provider list in README and core concepts
- Created blog post announcing Ollama support with type-safe examples

## [0.14.0] - 2025-07-28

### Added
- **llms.txt and llms-full.txt Documentation** (#51) - Machine-readable documentation format for LLMs
  - Created `llms.txt` with core DSPy.rb information for AI agents
  - Created comprehensive `llms-full.txt` with complete library details
  - Added links to documentation footer and README for easy access
  - Enables AI agents to better understand and work with DSPy.rb

- **AnthropicToolUseStrategy** - Improved handling of Anthropic's tool_use response format
  - Better JSON extraction from Anthropic's structured outputs
  - Enhanced compatibility with Claude's latest response formats
  - Improved test coverage for various response patterns

### Fixed
- Fixed Anthropic tool_use response format handling to properly extract JSON from content blocks
- Resolved Sorbet type checking issues in AnthropicToolUseStrategy tests
- Updated playwright-ruby-client dependency to fix OG image generation for documentation site
- Fixed OG image URL paths to include base_path for GitHub Pages deployment

### Changed
- Updated gemspec description for clarity
- Simplified language in documentation articles for better accessibility
- Improved strategy selection tests to focus on behavior rather than implementation details

## [0.13.0] - 2025-07-25

### Added
- **Token Usage Type Safety with T::Struct** - Convert token usage data to typed structs for better reliability
  - New `DSPy::LM::Usage` and `DSPy::LM::OpenAIUsage` structs for type-safe token usage
  - `UsageFactory` handles conversion from various formats (hashes, API response objects)
  - Automatic handling of OpenAI's nested details objects with proper type conversion
  - Token tracking now works reliably with VCR cassettes

### Fixed
- **Token Tracking with VCR** (#48) - Fixed token usage events not being emitted during VCR playback
  - Normalized usage data keys to symbols in both OpenAI and Anthropic adapters
  - Enhanced TokenTracker to handle both symbol and string keys defensively
  - Added comprehensive integration tests for token tracking with VCR

### Changed
- **BREAKING**: `Response#usage` now returns `DSPy::LM::Usage` struct instead of Hash
  - Access token counts via `.input_tokens`, `.output_tokens`, `.total_tokens` instead of hash keys
  - Use `.to_h` method on usage struct if you need a hash representation
  - OpenAI responses return `DSPy::LM::OpenAIUsage` with additional `prompt_tokens_details` and `completion_tokens_details`

### Migration Guide
If you were directly accessing usage data:
```ruby
# Before (0.12.0)
response.usage[:input_tokens]   # or response.usage['input_tokens']
response.usage[:output_tokens]  # or response.usage['output_tokens']

# After (0.13.0)
response.usage.input_tokens
response.usage.output_tokens
response.usage.to_h  # if you need hash format
```

## [0.12.0] - 2025-07-23

### Added
- **Raw Chat API for Benchmarking and Migration** (#47) - Enable running legacy prompts through DSPy's instrumentation pipeline
  - New `DSPy::LM#raw_chat` method for executing raw prompts without structured output features
  - Support for both array format and DSL format with `MessageBuilder`
  - Full instrumentation support - emits `dspy.lm.request` and `dspy.lm.tokens` events
  - Enables fair benchmarking between monolithic prompts and modular DSPy implementations
  - Facilitates gradual migration from legacy prompt systems
  - Streaming support via block parameter
  - Message validation with clear error messages

### Documentation
- Added comprehensive benchmarking guide at `/optimization/benchmarking-raw-prompts/`
- Added blog article explaining the raw_chat API and migration strategies
- Updated core concepts documentation with raw_chat usage examples

### Internal
- Extracted common instrumentation logic into reusable private methods
- Refactored existing `chat` method to use extracted instrumentation logic
- Added `DSPy::LM::MessageBuilder` class for clean message construction

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