# Claude AI Assistant Instructions for DSPy.rb

This document provides essential context and instructions for working with the DSPy.rb codebase. 
I want you to have a clear understanding of the library's architecture, dependencies, and how to work with it effectively.
I encourage you to apply a skeptical and honest approach to making decisions based on this information.

## Important: Developer Documentation
DSPy.rb is targeted towards developers so the user documentation under docs/*.md is the primary source of information.
When making changes make sure the developer docs are in sync with the changes.
Make sure the developer docs do not over promise or under promise the user.

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
  - **IMPORTANT**: alexrudall/ruby-openai is not the official Ruby SDK. The official SDK is: https://github.com/openai/openai-ruby

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

# CLAUDE.md - Ruby Method Writing Best Practices for dspy.rb

## Writing Methods Best Practices

When evaluating whether a Ruby method you implemented is good or not, use this checklist:

### 1. Readability First
Can you read the method and HONESTLY easily follow what it's doing? If yes, then stop here. Ruby emphasizes readability - your code should read like well-written prose.

### 2. Cyclomatic Complexity
Does the method have very high cyclomatic complexity? Check for:
- Deeply nested `if/elsif/else` chains
- Complex `case/when` statements
- Multiple guard clauses that obscure the main logic
- Nested loops with conditional logic

If complexity is high, consider extracting private methods or using Ruby patterns like early returns.

### 3. Ruby Idioms and Data Structures
Are there Ruby-specific patterns or data structures that would make this method cleaner?
- Use `Enumerable` methods (`map`, `select`, `reduce`, `each_with_object`) instead of manual loops
- Consider `Struct` or `Data` (Ruby 3.2+) for simple value objects
- Use `Set` for unique collections
- Leverage `Hash` with default values or blocks
- For DSPy components: consider using modules for mixins, delegation patterns for prompt chaining

### 4. Method Parameters
- Are there any unused parameters?
- Could keyword arguments make the method interface clearer?
- Should any positional arguments be converted to keyword arguments for clarity?
- For DSPy signatures: are prompt templates and parameters clearly separated?

### 5. Type Safety and Coercion
- Are there unnecessary `.to_s`, `.to_i`, `.to_a` calls that could be handled at method boundaries?
- Consider using Ruby 3+ RBS type signatures for critical interfaces
- For LLM responses: is type coercion happening at the right abstraction level?

### 6. Testability
Is the method easily testable with RSpec without heavy mocking?
- Avoid mocking LLM calls directly in unit tests - use VCR for integration tests
- Can you test the prompt construction logic separately from LLM execution?
- Are there clear inputs and outputs that can be asserted?
- For DSPy modules: can you test signature validation independently?

### 7. Dependencies and Side Effects
- Does the method have hidden dependencies on instance variables that could be parameters?
- Are there any class variables or global state dependencies?
- For LLM interactions: is the model configuration injected or hard-coded?
- Can API keys and endpoints be configured without modifying the method?

### 8. Naming Conventions
Brainstorm 3 better method names and evaluate:
- Does it follow Ruby conventions? (snake_case, predicate methods end with `?`, dangerous methods end with `!`)
- Is it consistent with DSPy terminology (e.g., `forward` for inference, `compile` for optimization)?
- Does it clearly indicate if it's a command (changes state) or query (returns value)?

## DSPy.rb Specific Considerations

### Method Extraction Guidelines
You SHOULD NOT extract a separate method unless:
- The extracted method represents a reusable DSPy component (Signature, Module, Optimizer)
- The method encapsulates prompt template logic that varies by use case
- The original method mixes LLM interaction with business logic that should be tested separately
- The method handles retry logic or error recovery that's reusable across different LLM calls

### Example Patterns

```ruby
# GOOD: Clear separation of concerns
class ChainOfThought < DSPy::Module
  def forward(input)
    reasoning = generate_reasoning(input)
    answer = extract_answer(reasoning)
    DSPy::Prediction.new(reasoning: reasoning, answer: answer)
  end

  private

  def generate_reasoning(input)
    # Focused on prompt construction
  end

  def extract_answer(reasoning)
    # Focused on parsing logic
  end
end

# BAD: Mixed concerns, hard to test
class ChainOfThought < DSPy::Module
  def forward(input)
    # 50 lines mixing prompt construction, API calls, parsing, and error handling
  end
end

```

## Project Management

### GitHub Issues
- Add GH issues to th DSPy.rb 1.0 Project and assign them to me

## Issue Writing Guidelines
- When writing issues write the title from the perspective of the user.

## Development Best Practices

### GitHub Issue References
- Follow GitHub good practices with issues, i.e., when working on issues make a reference in the commit message that way GitHub can link it in the web UI

