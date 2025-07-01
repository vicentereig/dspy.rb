# Claude AI Assistant Instructions for DSPy.rb

This document provides essential context and instructions for working with the DSPy.rb codebase.

## Important: Library Documentation

When working with external libraries in this codebase, **ALWAYS check the documentation for the specific version** used in the gemspec. This is critical because:

1. APIs can change between versions
2. Features may be added or removed
3. Configuration syntax may differ

### Key Libraries and Their Versions

#### Runtime Dependencies (from gemspec):
- **dry-configurable** (~> 1.0) - Configuration management
  - Docs: https://dry-rb.org/gems/dry-configurable/1.0/
  - Used for: Module configuration, nested settings blocks
  - Key patterns: `setting :name`, nested blocks for sub-configurations

- **dry-logger** (~> 1.0) - Structured logging
  - Docs: https://dry-rb.org/gems/dry-logger/1.0/
  - Used for: Application-wide logging with structured output

- **dry-monitor** (~> 1.0) - Event monitoring and instrumentation
  - Docs: https://dry-rb.org/gems/dry-monitor/1.0/
  - Used for: Event emission, instrumentation system

- **async** (~> 2.23) - Concurrent programming
  - Docs: https://github.com/socketry/async/tree/v2.23.0
  - Used for: Asynchronous LLM API calls

- **openai** (~> 0.9.0) - OpenAI API client
  - Docs: https://github.com/alexrudall/ruby-openai/tree/v0.9.0
  - Used for: ChatGPT/GPT-4 API integration

- **anthropic** (~> 1.1.0) - Anthropic API client
  - Docs: https://github.com/anthropics/anthropic-sdk-ruby/tree/v1.1.0
  - Used for: Claude API integration

- **sorbet-runtime** (~> 0.5) - Runtime type checking
  - Docs: https://sorbet.org/
  - Used for: Type safety throughout the codebase

- **polars-df** (~> 0.20.0) - DataFrame library
  - Docs: https://github.com/ankane/polars-ruby/tree/v0.20.0
  - Used for: Data processing in evaluations

#### Development Dependencies:
- **rspec** (~> 3.12) - Testing framework
- **vcr** (~> 6.2) - HTTP interaction recording
- **webmock** (~> 3.18) - HTTP request stubbing

## Common Tasks

### Running Tests
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/path/to/file_spec.rb

# Run with specific pattern
bundle exec rspec --pattern "**/instrumentation*"

# Run with coverage
bundle exec rspec --require spec_helper
```

### Code Quality
```bash
# Run linter (if configured)
bundle exec rubocop

# Type check with Sorbet
bundle exec srb tc
```

### Common Patterns in This Codebase

1. **Configuration Pattern**: Uses dry-configurable extensively
   ```ruby
   # CORRECT: Nested configuration blocks
   setting :instrumentation do
     setting :enabled, default: false
     setting :logger do
       setting :level, default: :info
     end
   end
   
   # WRONG: Separate configuration classes
   # Don't create InstrumentationConfig classes
   ```

2. **Instrumentation**: Event-driven architecture using dry-monitor
   ```ruby
   DSPy::Instrumentation.instrument('event.name', payload) do
     # work to be measured
   end
   ```

3. **Module System**: All DSPy modules inherit from DSPy::Module
   - Supports per-instance LM configuration
   - Uses Sorbet for type safety

## Architecture Notes

- The instrumentation system is configuration-driven (see `docs/production/observability.md`)
- LM providers are abstracted through a common interface in `lib/dspy/lm.rb`
- All events are registered in `lib/dspy/instrumentation.rb`
- Storage and registry systems support versioning and deployment

## Debugging Tips

1. Check library version compatibility when encountering unexpected behavior
2. Use `bundle exec` to ensure correct gem versions
3. The instrumentation system can help trace execution flow
4. VCR cassettes record API interactions for consistent testing

## Important Files

- `lib/dspy.rb` - Main module with configuration
- `lib/dspy/instrumentation.rb` - Event system and monitoring
- `lib/dspy/lm.rb` - Language model abstraction
- `docs/production/observability.md` - Instrumentation documentation

## Before Making Changes

1. Read the documentation for any library you're using directly
2. Check existing patterns in the codebase
3. Run tests to ensure nothing breaks
4. Follow the established configuration patterns (dry-configurable)
5. Consider backward compatibility when refactoring

## Version-Specific Documentation Links

When in doubt about a library's API:
1. Check the gemspec for the exact version constraint
2. Look for version-specific documentation (add `/tree/vX.Y.Z` to GitHub URLs)
3. Review the CHANGELOG for breaking changes between versions
4. Test behavior in `bundle exec irb` with the actual gem version