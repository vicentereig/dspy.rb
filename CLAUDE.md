# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

I want you to have a clear understanding of the library's architecture, dependencies, and how to work with it effectively.
I encourage you to apply a skeptical and honest approach to making decisions based on this information.
Always follow Test-Driven Development (TDD) practices when implementing new features.

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
- **dry-configurable** (~> 1.0) - Configuration management ([docs](https://dry-rb.org/gems/dry-configurable/1.0/))
- **dry-logger** (~> 1.0) - Structured logging ([docs](https://dry-rb.org/gems/dry-logger/1.0/))
- **dry-monitor** (~> 1.0) - Event monitoring ([docs](https://dry-rb.org/gems/dry-monitor/1.0/))
- **async** (~> 2.23) - Concurrent programming ([docs](https://github.com/socketry/async/tree/v2.23.0))
- **openai** (~> 0.16.0) - Official OpenAI SDK ([docs](https://github.com/openai/openai-ruby/tree/v0.16.0))
- **anthropic** (~> 1.5.0) - Official Anthropic SDK ([docs](https://github.com/anthropics/anthropic-sdk-ruby/tree/v1.5.0))
- **sorbet-runtime** (~> 0.5) - Runtime type checking ([docs](https://sorbet.org/))
- **polars-df** (~> 0.20.0) - DataFrame library ([docs](https://github.com/ankane/polars-ruby/tree/v0.20.0))
- **informers** (~> 1.2) - Local embeddings ([docs](https://github.com/ankane/informers))
- **sorbet-schema** (~> 0.3) - Schema validation ([docs](https://github.com/maxveldink/sorbet-schema))

#### Development Dependencies:
- **rspec** (~> 3.12) - Testing framework
- **vcr** (~> 6.2) - HTTP interaction recording
- **webmock** (~> 3.18) - HTTP request stubbing
- **byebug** (~> 11.1) - Debugging tool
- **dotenv** (~> 2.8) - Environment variable management

## Documentation Links

### User Documentation
- [Getting Started](docs/src/getting-started/index.md)
  - [Installation](docs/src/getting-started/installation.md)
  - [Quick Start](docs/src/getting-started/quick-start.md)
  - [First Program](docs/src/getting-started/first-program.md)
  - [Core Concepts](docs/src/getting-started/core-concepts.md)
- [Core Concepts](docs/src/core-concepts/index.md)
  - [Signatures](docs/src/core-concepts/signatures.md)
  - [Modules](docs/src/core-concepts/modules.md)
  - [Predictors](docs/src/core-concepts/predictors.md)
  - [Memory](docs/src/core-concepts/memory.md)
  - [Toolsets](docs/src/core-concepts/toolsets.md)
  - [CodeAct Agent](docs/src/core-concepts/codeact.md)
  - [Multimodal](docs/src/core-concepts/multimodal.md)
  - [Examples](docs/src/core-concepts/examples.md)
- [Features](docs/src/features/)
- [Advanced Topics](docs/src/advanced/index.md)
  - [Complex Types](docs/src/advanced/complex-types.md)
  - [Memory Systems](docs/src/advanced/memory-systems.md)
  - [Custom Toolsets](docs/src/advanced/custom-toolsets.md)
  - [Custom Metrics](docs/src/advanced/custom-metrics.md)
  - [Pipelines](docs/src/advanced/pipelines.md)
  - [RAG](docs/src/advanced/rag.md)
  - [Rails Integration](docs/src/advanced/rails-integration.md)
  - [Stateful Agents](docs/src/advanced/stateful-agents.md)
  - [Python Comparison](docs/src/advanced/python-comparison.md)
- [Optimization](docs/src/optimization/index.md)
  - [Evaluation](docs/src/optimization/evaluation.md)
  - [MIPROv2](docs/src/optimization/miprov2.md)
  - [Prompt Optimization](docs/src/optimization/prompt-optimization.md)
  - [Benchmarking](docs/src/optimization/benchmarking-raw-prompts.md)
- [Production](docs/src/production/index.md)
  - [Observability](docs/src/production/observability.md)
  - [Storage](docs/src/production/storage.md)
  - [Registry](docs/src/production/registry.md)
  - [Troubleshooting](docs/src/production/troubleshooting.md)

### Blog & Articles
- [Run LLMs Locally with Ollama](docs/src/_articles/run-llms-locally-with-ollama-and-type-safe-ruby.md)
- [Type-Safe Prediction Objects](docs/src/_articles/type-safe-prediction-objects.md)
- [Union Types in Agentic Workflows](docs/src/_articles/union-types-agentic-workflows.md)
- [ReAct Agent Tutorial](docs/src/_articles/react-agent-tutorial.md)
- [CodeAct Dynamic Code Generation](docs/src/_articles/codeact-dynamic-code-generation.md)
- [JSON Parsing Reliability](docs/src/_articles/json-parsing-reliability.md)
- [Program of Thought Deep Dive](docs/src/_articles/program-of-thought-deep-dive.md)
- [Ruby Idiomatic APIs](docs/src/_articles/ruby-idiomatic-apis.md)
- [Raw Chat API](docs/src/_articles/raw-chat-api.md)
- [Under the Hood: JSON Extraction](docs/src/_articles/under-the-hood-json-extraction.md)

### Architecture Decision Records (ADRs)
- [ADR Index](adr/README.md)
- [001: Prediction Type Conversion Design](adr/001-prediction-type-conversion-design.md)
- [002: Prediction Refactoring](adr/002-prediction-refactoring-recommendation.md)
- [003: Ruby Idiomatic API Design](adr/003-ruby-idiomatic-api-design.md)
- [004: Single Field Union Types](adr/004-single-field-union-types.md)
- [005: Multi-Method Tool System](adr/005-multi-method-tool-system.md)
- [006: Unified Image Type](adr/006-unified-image-type-vs-provider-specific-types.md)
- [Development Learnings](adr/LEARNINGS.md) - Accumulated knowledge from development
- [Architecture & Provider Integration](adr/ARCHITECTURE.md) - System design and provider strategies

## Common Tasks

### Development Setup
```bash
# Install dependencies
bundle install

# Set up environment variables for API access
export OPENAI_API_KEY=your-openai-api-key
export ANTHROPIC_API_KEY=your-anthropic-api-key

# Run interactive console
bundle exec irb -r ./lib/dspy.rb
```

### Running Tests
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/path/to/file_spec.rb

# Run a single test by line number
bundle exec rspec spec/path/to/file_spec.rb:42

# Run only unit tests (fast)
bundle exec rspec spec/unit

# Run only integration tests (slower, uses VCR)
bundle exec rspec spec/integration
```

### Building and Releasing
```bash
# Build the gem locally
gem build dspy.gemspec

# Install locally built gem
gem install ./dspy-*.gem

# Push to RubyGems (maintainers only)
gem push dspy-VERSION.gem
```

## Development Guidelines

### Ruby 3.3 Development Best Practices

#### Before Coding
- **BP-1 (MUST)** Ask the user clarifying questions.
- **BP-2 (SHOULD)** Draft and confirm an approach for complex work.  
- **BP-3 (SHOULD)** If ≥ 2 approaches exist, list clear pros and cons.

#### While Coding
- **C-1 (MUST)** Follow TDD: scaffold stub -> write failing test -> implement.
- **C-2 (MUST)** Name methods with existing domain vocabulary for consistency.  
- **C-3 (SHOULD NOT)** Introduce classes when small testable methods suffice.  
- **C-4 (SHOULD)** Prefer simple, composable, testable methods.
- **C-5 (MUST)** Use Sorbet type annotations for critical interfaces
- **C-6 (MUST)** Use Ruby 3.3 features appropriately: `Data` class, pattern matching, etc.
- **C-7 (SHOULD NOT)** Add inline comments except for critical caveats; rely on self-explanatory code. YARD docs on public APIs are encouraged.
- **C-8 (SHOULD)** Default to simple classes; use modules for shared behavior and mixins. 
- **C-9 (SHOULD NOT)** Extract a new method unless it will be reused elsewhere.

#### Testing
- **T-1 (MUST)** For any API change, add/extend integration tests in `spec/integration/*.rb`.
- **T-2 (MUST)** ALWAYS separate pure-logic unit tests from LLM-touching integration tests.
- **T-3 (SHOULD)** Prefer integration tests over heavy mocking.  
- **T-4 (SHOULD)** Unit-test complex algorithms thoroughly.
- **T-5 (SHOULD)** Test the entire structure in one assertion if possible

#### Code Organization
- **O-1 (SHOULD)** Group related functionality in logical subdirectories (`tools/`, `memory/`, `agents/`).

#### Tooling Gates
- **G-1 (MUST)** `bundle exec rspec` passes.
- **G-2 (MUST)** Documentation site builds successfully before pushing changes.

### Documentation Site Build Verification

When making changes to the documentation site (anything in `/docs/`), **ALWAYS** verify the build works locally before pushing:

```bash
# Navigate to docs directory
cd docs

# Install dependencies (if not already done)
npm ci
bundle install

# Build the site locally
BRIDGETOWN_ENV=production npm run build

# If build succeeds, you're ready to push
# If build fails, fix the issues before pushing
```

### Git Best Practices

- **GH-1 (MUST)** Use Conventional Commits format: https://www.conventionalcommits.org/en/v1.0.0
- **GH-2 (SHOULD NOT)** Refer to Claude or Anthropic in commit messages.
- **GH-3 (MUST)** Reference GitHub issues in commit messages (e.g., `fix #123`, `ref #456`)

## Writing Methods Best Practices

When evaluating whether a Ruby method is good, use this checklist:

1. **Readability First** - Can you read the method and easily follow what it's doing?
2. **Cyclomatic Complexity** - Check for deeply nested conditions, complex case statements
3. **Ruby Idioms** - Use `Enumerable` methods, `Data` class, appropriate data structures
4. **Method Parameters** - Use keyword arguments for clarity, avoid unused parameters
5. **Type Safety** - Use Sorbet type signatures for critical interfaces
6. **Testability** - Is the method easily testable without heavy mocking?
7. **Dependencies** - Avoid hidden dependencies on instance/class variables
8. **Naming** - Follow Ruby conventions (snake_case, `?` for predicates, `!` for dangerous)

## Writing Tests Best Practices

1. **SHOULD** parameterize inputs; never embed unexplained literals
2. **SHOULD NOT** add a test unless it can fail for a real defect
3. **SHOULD** ensure test description matches what the assert verifies
4. **SHOULD** compare to independent expectations, not method output as oracle
5. **SHOULD** express invariants/axioms rather than single cases when practical
6. **SHOULD** test edge cases, realistic input, unexpected input, boundaries
7. **MUST** Use VCR for recording LLM interactions in integration tests

## Project Management

### GitHub Issues
- Add GH issues to the DSPy.rb 1.0 Project and assign them to me
- When writing issues, adopt the user's perspective
- Start with a succinct explanation of importance
- Follow with comprehensive technical details

### Development Best Practices
- **ALWAYS** check if the issue you're working on is already implemented before starting work
- Before implementing a feature, search the codebase for existing implementations
- Run tests to verify implementation status: `bundle exec rspec`
- Use GitHub commit message shortcuts to close issues: `close #123`, `fix #123`

## Remember Shortcuts

### QNEW
```
Understand all BEST PRACTICES listed in CLAUDE.md.
Your code SHOULD ALWAYS follow these best practices.
```

### QPLAN
```
Analyze similar parts of the codebase and determine whether your plan:
- is consistent with rest of codebase
- introduces minimal changes
- reuses existing code
```

### QCODE
```
Implement your plan and make sure your new tests pass.
Always run tests to make sure you didn't break anything else.
Always run `bundle exec rspec` to ensure all tests pass.
```

### QCHECK
```
You are a SKEPTICAL senior software engineer.
Perform this analysis for every MAJOR code change you introduced:
1. CLAUDE.md checklist Writing Methods Best Practices.
2. CLAUDE.md checklist Writing Tests Best Practices.
3. CLAUDE.md checklist Implementation Best Practices.
```

### QCHECKM
```
You are a SKEPTICAL senior software engineer.
Perform this analysis for every MAJOR method you added or edited:
1. CLAUDE.md checklist Writing Methods Best Practices.
```

### QCHECKT
```
You are a SKEPTICAL senior software engineer.
Perform this analysis for every MAJOR test you added or edited:
1. CLAUDE.md checklist Writing Tests Best Practices.
```

### QUX
```
Imagine you are a human UX tester of the feature you implemented. 
Output a comprehensive list of scenarios you would test, sorted by highest priority.
```

### QGIT
```
Add all changes to staging, create a commit, and push to remote.
Follow Conventional Commits format: https://www.conventionalcommits.org/en/v1.0.0
```

## Test Debugging Learnings

### Event System Architecture Best Practices

**Problem**: Event logging tests failing because `emit_log` was commented out.

**Solution**: Implemented publisher-subscriber pattern where logger becomes an event consumer:
```ruby
def self.events
  @event_registry ||= DSPy::EventRegistry.new.tap do |registry|
    # Subscribe logger to all events - use a proc that calls logger each time
    # to support mocking in tests
    registry.subscribe('*') { |event_name, attributes| 
      emit_log(event_name, attributes) if logger
    }
  end
end
```

**Key Learning**: Don't call logging directly in event system. Let logger subscribe to events for complete coverage.


**Key Learning**: With Sorbet runtime checks enabled, integration tests should use real instances with VCR, not mocks.

### VCR Test Configuration Pattern

**Pattern**: For integration tests touching LLMs:
- Use real `DSPy::LM` instances, not mocks
- Add VCR cassette configurations: `vcr: { cassette_name: "descriptive_name" }`
- Reduce generation counts for faster testing: `config.num_generations = 2; config.population_size = 2`
- No need for API key skip guards - let VCR handle missing keys gracefully

### Test Isolation Issues

**Problem**: Some tests pass in isolation but fail in the full suite.

**Root Cause**: Singleton patterns (`@event_registry`) capture references at creation time, causing issues with mocking.

**Solution**: Design singletons to resolve dependencies dynamically:
```ruby
# ❌ Bad - captures logger reference at creation time
registry.subscribe('*') { emit_log(event_name, attributes) }

# ✅ Good - resolves logger each time
registry.subscribe('*') { emit_log(event_name, attributes) if logger }
```

**Key Learning**: Avoid capturing method/instance references in closures within singleton initialization.
