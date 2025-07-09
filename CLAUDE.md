# Claude AI Assistant Instructions for DSPy.rb

This document provides essential context and instructions for working with the DSPy.rb codebase. 
I want you to have a clear understanding of the library's architecture, dependencies, and how to work with it effectively.
I encourage you to apply a skeptical and honest approach to making decisions based on this information.

## Important: Developer Documentation
DSPy.rb is targeted towards developers so the user documentation under docs/*.md is the primary source of information.
When making changes make sure the developer docs are in sync with the changes.
Make sure the developer docs do not over promise or under promise the user.

## Core Principles
- **Be skeptical of AI-generated patterns**: Always verify API methods and implementations against actual code
- **Trust the type system**: When using Sorbet-runtime, avoid redundant runtime checks
- **Use T::Struct over Hashes**: Define proper types for complex data structures
- **Default to simple solutions**: Start simple, optimize only when necessary
- **Avoid unnecessary fallbacks**: Trust types and contracts instead of defensive programming

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

## Library Usage Guidelines

- **Always check gem documentation for the version specified in Gemfile**: Before using any library methods or APIs, verify the correct syntax and available features for the exact version we're using
- **Never assume API syntax**: Different gem versions can have different APIs - always reference the documentation for our specific version
- **When in doubt, search the codebase first**: Look for existing usage patterns before implementing new library calls
- **Examples of version-specific differences**:
  - OpenAI gem versions may have completely different APIs between major versions
  - Check the specific version docs in the gemspec before implementation

---

# Ruby 3.3 Development Guidelines

## Implementation Best Practices

### 0 — Purpose  

These rules ensure maintainability, safety, and developer velocity for Ruby 3.3 development. 
**MUST** rules are enforced by CI; **SHOULD** rules are strongly recommended.

---

### 1 — Before Coding

- **BP-1 (MUST)** Ask the user clarifying questions.
- **BP-2 (SHOULD)** Draft and confirm an approach for complex work.  
- **BP-3 (SHOULD)** If ≥ 2 approaches exist, list clear pros and cons.

---

### 2 — While Coding

- **C-1 (MUST)** Follow TDD: scaffold stub -> write failing test -> implement.
- **C-2 (MUST)** Name methods with existing domain vocabulary for consistency.  
- **C-3 (SHOULD NOT)** Introduce classes when small testable methods suffice.  
- **C-4 (SHOULD)** Prefer simple, composable, testable methods.
- **C-5 (MUST)** Use Sorbet type annotations for critical interfaces
  ```ruby
  sig { params(user_id: String).returns(T.nilable(User)) }   # ✅ Good
  def find_user(user_id); end                                # ❌ Bad (no type info)
  ```  
- **C-6 (MUST)** Use Ruby 3.3 features appropriately: `Data` class, pattern matching, etc.
- **C-7 (SHOULD NOT)** Add comments except for critical caveats; rely on self-explanatory code.
- **C-8 (SHOULD)** Default to simple classes; use modules for shared behavior and mixins. 
- **C-9 (SHOULD NOT)** Extract a new method unless it will be reused elsewhere, is the only way to unit-test otherwise untestable logic, or drastically improves readability of an opaque block.

---

### 3 — Testing

- **T-2 (MUST)** For any API change, add/extend integration tests in `spec/integration/*.rb`.
- **T-3 (MUST)** ALWAYS separate pure-logic unit tests from LLM-touching integration tests.
- **T-4 (SHOULD)** Prefer integration tests over heavy mocking.  
- **T-5 (SHOULD)** Unit-test complex algorithms thoroughly.
- **T-6 (SHOULD)** Test the entire structure in one assertion if possible
  ```ruby
  expect(result).to eq([value]) # Good

  expect(result).to have(1).item    # Bad
  expect(result.first).to eq(value) # Bad
  ```

---

### 4 — Database/Storage

- **D-1 (MUST)** Use dependency injection for storage backends to support testing.  
- **D-2 (SHOULD)** Use structured data types (`Data` class, `Struct`) for complex data rather than raw hashes.

---

### 5 — Code Organization

- **O-2 (SHOULD)** Group related functionality in logical subdirectories (`tools/`, `memory/`, `agents/`).

---

### 6 — Tooling Gates

- **G-1 (MUST)** `bundle exec rubocop` passes.  
- **G-2 (MUST)** `bundle exec srb tc` passes.
- **G-3 (MUST)** `bundle exec rspec` passes.

---

### 7 - Git

- **GH-1 (MUST)** Use Conventional Commits format when writing commit messages: https://www.conventionalcommits.org/en/v1.0.0
  - Format: `<type>[optional scope]: <description>`
  - Types: `fix:`, `feat:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`
  - Breaking changes: Add `!` after type or `BREAKING CHANGE:` in footer
- **GH-2 (SHOULD NOT)** Refer to Claude or Anthropic in commit messages.
- **GH-3 (SHOULD)** Reference issues in commits: `fix: resolve parsing issue (#42)`
- **GH-4 (SHOULD)** Keep commits atomic - one logical change per commit

---

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
- Consider using Sorbet type signatures for critical interfaces
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

## Common Anti-Patterns to Avoid

### Avoid Unnecessary Fallbacks
```ruby
# ❌ BAD: Unnecessary fallback logic
def process(result)
  if result.documents.is_a?(Array)
    result.documents
  else
    []  # Don't do this!
  end
end

# ✅ GOOD: Trust the types
def process(result)
  result.documents  # Already guaranteed to be an Array by signature
end
```

### Type Definitions
```ruby
# ❌ BAD: Generic hash types
const :metadata, T::Hash[Symbol, T.untyped]

# ✅ GOOD: Specific struct
class Metadata < T::Struct
  const :source, String
  const :timestamp, Time
  const :version, Integer
end
const :metadata, Metadata
```

### Error Handling
- DO NOT implement fallback logic unless explicitly required by business logic
- Fallbacks add complexity and cognitive load
- Trust the type system (Sorbet runtime) - don't add defensive `respond_to?` checks

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

---

## Testing Best Practices

### VCR Recording for External APIs
- **ALWAYS use VCR** for tests that make external API calls
- DO NOT mock DSPy or LLM responses - re-record cassettes instead
- Example:
  ```ruby
  it 'performs synthesis', vcr: { cassette_name: 'synthesis_response' } do
    # Test code that calls OpenAI/Anthropic
  end
  ```

### Mock at the Right Level
```ruby
# ✅ GOOD: Mock DSPy module with proper struct
mock_result = Struct.new(:documents, :search_strategy, :total_results).new(
  [DocumentSearchSignature::DocumentChunk.new(
    content: 'Test content',
    relevance_score: 0.9,
    metadata: {},
    # ... other required fields
  )],
  'sequential',
  1
)
allow(search_module).to receive(:forward).and_return(mock_result)

# ❌ BAD: Mocking with plain hashes
allow(search_module).to receive(:forward).and_return({
  documents: [{ content: 'Test' }]  # Type mismatch!
})
```

## Writing Tests Best Practices

When evaluating whether a test you've implemented is good or not, use this checklist:

1. **SHOULD** parameterize inputs; never embed unexplained literals such as `42` or `"foo"` directly in the test.
2. **SHOULD NOT** add a test unless it can fail for a real defect. Trivial asserts (e.g., `expect(2).to eq(2)`) are forbidden.
3. **SHOULD** ensure the test description states exactly what the final expect verifies. If the wording and assert don't align, rename or rewrite.
4. **SHOULD** compare results to independent, pre-computed expectations or to properties of the domain, never to the method's output re-used as the oracle.
5. **SHOULD** follow the same lint, type-safety, and style rules as prod code (RuboCop, Sorbet, etc.).
6. **SHOULD** express invariants or axioms (e.g., commutativity, idempotence, round-trip) rather than single hard-coded cases whenever practical.
7. Unit tests for a method should be grouped under `describe MethodName` or `describe '#method_name'`.
8. Use `anything` or specific matchers when testing for parameters that can be variable (e.g. dynamic IDs).
9. **ALWAYS** use strong assertions over weaker ones e.g. `expect(x).to eq(1)` instead of `expect(x).to be >= 1`.
10. **SHOULD** test edge cases, realistic input, unexpected input, and value boundaries.
11. **SHOULD NOT** test conditions that are caught by Sorbet type checking.
12. **MUST** Use VCR for recording LLM interactions in integration tests:
```ruby
# Good: VCR-recorded integration test
it "generates valid reasoning", vcr: { cassette_name: "chain_of_thought_reasoning" } do
  result = chain_of_thought.forward("What is 2+2?")
  expect(result.reasoning).to include("step")
  expect(result.answer).to eq("4")
end

# Bad: Mocked LLM calls in unit tests
it "calls LLM with correct prompt" do
  expect(lm).to receive(:generate).with(hash_including(prompt: anything))
  chain_of_thought.forward("What is 2+2?")
end
```

---

## Debugging Best Practices

1. **Check for Existing Issues**: When encountering errors, always check GitHub issues first
2. **Read Error Messages Carefully**: Most errors indicate missing dependencies or configuration
3. **Verify Dependencies**: Ensure all runtime dependencies are properly installed
4. **Test Locally First**: Run tests and linters before pushing changes
5. **Use DSPy.logger for Output**: Configure logging appropriately for debugging
   - Never use `puts`, `print`, or `p` in library code
   - Use `DSPy.logger.debug` for detailed debugging info
   - Use `DSPy.logger.info` for important operational messages
   - Use `DSPy.logger.warn` for warnings
   - Use `DSPy.logger.error` for errors

## Code Organization

DSPy.rb follows a modular architecture:

- `lib/dspy.rb` - Main entry point and configuration
- `lib/dspy/` - Core library components
  - `agents/` - Multi-step agent implementations (ReAct, CodeAct, etc.)
  - `memory/` - Memory management and persistence
  - `tools/` - Tool definitions and toolsets
  - `lm/` - Language model abstractions and clients
  - `teleprompt/` - Optimization and fine-tuning
- `spec/` - Test suite
  - `integration/` - Integration tests with VCR recordings
  - `unit/` - Fast unit tests
- `docs/` - Developer documentation

---

## Project Management

### GitHub Issues
- Add GH issues to the DSPy.rb 1.0 Project and assign them to me

## Issue Writing Guidelines

- Write issue titles from the user's perspective (what they want to achieve, not how to implement it)
- Start with WHY: First paragraph should explain the user benefit and value
- Use clear, simple language without technical jargon in the problem statement
- Avoid grandiose promises or overselling the feature
- Structure issues as: User Problem → Value Proposition → Implementation Details
- Examples:
  - ❌ "Implement DSPy ChainOfThought for query analysis"  
  - ✅ "Enable step-by-step reasoning for complex AI tasks"
  - ❌ "Add Redis caching layer for performance optimization"  
  - ✅ "Speed up repeated AI operations with intelligent caching"

## Development Best Practices

### AI Development Guidelines
1. **Be Skeptical of AI-Generated Code**: Always verify API methods, patterns, and implementations
2. **Check Documentation First**: Before using any library feature, check the docs for your version
3. **Verify Against Real Code**: Look at actual implementations and tests, not just documentation
4. **Predictor Selection**:
   - Use `DSPy::Predict` for simple, fast classification/extraction
   - Use `DSPy::ChainOfThought` for reasoning/complex tasks
   - Use `DSPy::ReAct` only when tools are needed for external actions
   - Consider performance: Predict < ChainOfThought < ReAct < CodeAct

### GitHub Issue References
- Follow GitHub good practices with issues, i.e., when working on issues make a reference in the commit message that way GitHub can link it in the web UI
- Use conventional commits format with issue references: `feat: add new feature (#123)`

---

## Remember Shortcuts

Remember the following shortcuts which the user may invoke at any time.

### QNEW

When I type "qnew", this means:

```
Understand all BEST PRACTICES listed in CLAUDE.md.
Your code SHOULD ALWAYS follow these best practices.
```

### QPLAN
When I type "qplan", this means:
```
Analyze similar parts of the codebase and determine whether your plan:
- is consistent with rest of codebase
- introduces minimal changes
- reuses existing code
```

## QCODE

When I type "qcode", this means:

```
Implement your plan and make sure your new tests pass.
Always run tests to make sure you didn't break anything else.
Always run `bundle exec rubocop --autocorrect` on the newly created files to ensure standard formatting.
Always run `bundle exec srb tc` to make sure type checking passes.
Always run `bundle exec rspec` to ensure all tests pass.
```

### QCHECK

When I type "qcheck", this means:

```
You are a SKEPTICAL senior software engineer.
Perform this analysis for every MAJOR code change you introduced (skip minor changes):

1. CLAUDE.md checklist Writing Methods Best Practices.
2. CLAUDE.md checklist Writing Tests Best Practices.
3. CLAUDE.md checklist Implementation Best Practices.
```

### QCHECKM

When I type "qcheckm", this means:

```
You are a SKEPTICAL senior software engineer.
Perform this analysis for every MAJOR method you added or edited (skip minor changes):

1. CLAUDE.md checklist Writing Methods Best Practices.
```

### QCHECKT

When I type "qcheckt", this means:

```
You are a SKEPTICAL senior software engineer.
Perform this analysis for every MAJOR test you added or edited (skip minor changes):

1. CLAUDE.md checklist Writing Tests Best Practices.
```

### QUX

When I type "qux", this means:

```
Imagine you are a human UX tester of the feature you implemented. 
Output a comprehensive list of scenarios you would test, sorted by highest priority.
```

### QGIT

When I type "qgit", this means:

```
Add all changes to staging, create a commit, and push to remote.

Follow this checklist for writing your commit message:
- SHOULD use Conventional Commits format: https://www.conventionalcommits.org/en/v1.0.0
- SHOULD NOT refer to Claude or Anthropic in the commit message.
- SHOULD structure commit message as follows:
<type>[optional scope]: <description>
[optional body]
[optional footer(s)]
- commit SHOULD contain the following structural elements to communicate intent: 
fix: a commit of the type fix patches a bug in your codebase (this correlates with PATCH in Semantic Versioning).
feat: a commit of the type feat introduces a new feature to the codebase (this correlates with MINOR in Semantic Versioning).
BREAKING CHANGE: a commit that has a footer BREAKING CHANGE:, or appends a ! after the type/scope, introduces a breaking API change (correlating with MAJOR in Semantic Versioning). A BREAKING CHANGE can be part of commits of any type.
types other than fix: and feat: are allowed, for example @commitlint/config-conventional (based on the Angular convention) recommends build:, chore:, ci:, docs:, style:, refactor:, perf:, test:, and others.
footers other than BREAKING CHANGE: <description> may be provided and follow a convention similar to git trailer format.
```

---

## Best Practices Learned from Experience

### Signature Pattern
```ruby
class MySignature < DSPy::Signature
  description "Clear task description"
  
  # Use T::Enum for controlled outputs
  class MyEnum < T::Enum
    enums do
      Option1 = new('option1')
      Option2 = new('option2')
    end
  end
  
  # Use T::Struct for complex outputs
  class MyStruct < T::Struct
    const :field1, String
    const :field2, Integer
  end
  
  input do
    const :input_field, String, desc: "Description for LLM"
    const :optional_field, T.nilable(String)
  end
  
  output do
    const :result, MyEnum
    const :details, T::Array[MyStruct]
  end
end
```

### Module Pattern
```ruby
class MyModule < DSPy::Module
  def initialize
    super()
    @predictor = DSPy::Predict.new(MySignature)  # or ChainOfThought, ReAct
  end
  
  def forward(input:)
    @predictor.forward(input: input)
  end
end
```

### Toolset Pattern
```ruby
class MyToolset < DSPy::Tools::Toolset
  toolset_name "my_tools"
  
  tool :operation_one, description: "Does something"
  
  sig { params(input: String).returns(String) }
  def operation_one(input:)
    # Implementation
  end
end

# Usage with ReAct
toolset = MyToolset.new
agent = DSPy::ReAct.new(
  signature: MySignature,
  tools: toolset.class.to_tools  # Note: class method
)
```

### Key DSPy.rb Patterns to Remember
- Signatures define inputs/outputs using `input {}` and `output {}` blocks with Sorbet types
- Modules inherit from `DSPy::Module` and implement `forward` method
- Results are already properly typed - don't create unnecessary wrapper methods
- Use appropriate predictor for your use case (Predict vs ChainOfThought vs ReAct)
- Tool names in toolsets are prefixed with the toolset name
- Always use T::Struct for complex nested data instead of hashes
