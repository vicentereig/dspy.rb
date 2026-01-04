# DSPy.rb Architecture and Provider Integration

This document details the architectural decisions and provider-specific implementation strategies for DSPy.rb.

## Table of Contents
- [LLM Provider Integration Strategy](#llm-provider-integration-strategy)
- [System Architecture](#system-architecture)
- [Configuration Patterns](#configuration-patterns)
- [Event-Driven Architecture](#event-driven-architecture)

---

## LLM Provider Integration Strategy

### Current State Assessment (July 2025)

**Anthropic/Claude - Excellent Foundation:**
- Comprehensive 4-pattern JSON extraction system with extensive test coverage
- Recent improvements (July 2025) show active development and solid architecture
- Smart prefilling strategy and JSON detection heuristics
- Model-specific behavior detection for optimal performance

**OpenAI - Strong Foundation (Implemented July 2025):**
- ✅ Native structured output support (`response_format: { type: "json_schema" }`)
- ✅ Automatic JSON schema conversion from DSPy signatures
- ✅ Model compatibility detection for structured outputs
- ✅ High-priority strategy (100) for reliable JSON extraction
- ⚠️ Function/tool calling integration not yet implemented (separate feature)

### Strategic Approach

- **Explicit over implicit**: Prefer clear configuration over black-box auto-detection
- **Provider-specific optimization**: Leverage each provider's strengths rather than lowest common denominator
- **User control**: Provide override options for advanced users
- **Incremental improvement**: Start with high-impact changes (OpenAI structured outputs) before complex detection systems

### Implementation Priorities

1. **OpenAI Structured Outputs** (✅ Completed July 2025)
   - Added native `response_format` support to OpenAI adapter
   - Converts DSPy signatures to OpenAI JSON schema format
   - Maintains backward compatibility with explicit opt-in

2. **Provider Detection** (Strategic Value)
   - Simple capability detection for choosing optimal strategies
   - Configuration overrides for user control
   - Clear debugging and visibility into strategy selection

3. **Enhanced Reliability** (Long-term Value)
   - Retry mechanisms with progressive fallback
   - Multiple extraction strategies for edge cases
   - Performance monitoring and success rate tracking

### Lessons Learned

**Over-Engineering Warning:**
- Complex auto-detection systems introduce maintenance burden
- User complaints about JSON parsing failures are rare in practice
- Current Anthropic implementation is already excellent
- Focus on documented provider gaps rather than theoretical problems

**Architectural Principles:**
- Provider-specific code paths are preferable to complex abstraction layers
- Explicit configuration beats magical behavior
- User education and documentation can solve many perceived problems
- Performance and reliability improvements should be measurable and user-facing

---

## System Architecture

### Module Organization

DSPy.rb follows a modular architecture with clear separation of concerns:

```
lib/dspy/
├── agents/       # Multi-step agent implementations (ReAct core, CodeAct in dspy-code_act)
├── lm/           # Language model abstractions and adapters
├── memory/       # Memory management and persistence
├── teleprompt/   # Optimization and fine-tuning
├── tools/        # Tool definitions and toolsets
└── subscribers/  # Observability integrations (DataDog, OTEL)
```

### Core Components

1. **Language Model Abstraction** (`lib/dspy/lm.rb`)
   - Common interface for all LLM providers
   - Provider-specific adapters for OpenAI, Anthropic, etc.
   - Automatic retry and error handling

2. **Module System** (`lib/dspy/module.rb`)
   - All DSPy modules inherit from DSPy::Module
   - Supports per-instance LM configuration via dry-configurable
   - Composable building blocks for complex pipelines

3. **Signature System** (`lib/dspy/signature.rb`)
   - Type-safe input/output specifications
   - Automatic JSON schema generation
   - Provider-specific optimization strategies

4. **Instrumentation System** (`lib/dspy/instrumentation.rb`)
   - Event-driven architecture using dry-monitor
   - Pluggable subscribers for different observability platforms
   - Performance tracking and debugging support

---

## Configuration Patterns

### Dry-Configurable Usage

DSPy.rb uses dry-configurable extensively for clean configuration management:

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

### Module-Level Configuration

All DSPy modules support per-instance configuration:

```ruby
module = DSPy::ChainOfThought.new(SignatureClass)
module.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4')
  config.temperature = 0.7
end
```

This pattern allows:
- Runtime reconfiguration
- Better testing isolation
- Multiple module instances with different settings
- Fallback to global configuration when not specified

---

## Event-Driven Architecture

### Instrumentation Events

DSPy.rb uses an event-driven architecture for observability:

```ruby
DSPy::Instrumentation.instrument('lm.request', payload) do
  # work to be measured
end
```

### Registered Events

Key events emitted by the system:
- `lm.request` - LLM API request initiated
- `lm.response` - LLM API response received
- `lm.error` - LLM API error occurred
- `module.forward` - Module forward pass executed
- `signature.validate` - Signature validation performed
- `cache.hit` / `cache.miss` - Cache operations

### Subscriber Pattern

Observability platforms integrate via subscribers:
- DataDog subscriber for APM integration
- OpenTelemetry subscriber for distributed tracing
- Custom subscribers for application-specific needs

Each subscriber can:
- Filter events of interest
- Transform event data to platform-specific format
- Handle batching and async delivery
- Manage connection lifecycle

---

## Storage and Registry Architecture

### Storage System

The storage system supports multiple backends:
- In-memory storage for development/testing
- Redis for production deployments
- File-based storage for simple deployments

Key features:
- Versioning support for module deployments
- Automatic serialization/deserialization
- TTL support for cache expiration
- Namespace isolation for multi-tenant deployments

---

## Current Edge Cases (Baseline Jan 4, 2026)

As of January 4, 2026, the following behaviors are known and are addressed by the hardening plan:

- Module-scoped event subscriptions are instance-bound and retained by the event registry; they are not auto-released on GC, so explicit `unsubscribe_module_events` is required for cleanup.
- LLM request correlation uses `Thread.current` for `request_id` and timing; concurrent fibers on the same thread can overwrite or clear metadata.
- Structured outputs selection is coupled to adapter class names/instance variables and ignores `data_format`, so TOON can be wrapped in JSON-only structured prompts.
- Prompt rendering reads `DSPy.config.lm` at render time; changing global config can change prompts across threads.
- Modules/predictors carry mutable state (`@last_input_values`, `@demos`, subscription queues, cached LMs) and are not safe to share across threads without cloning.

## Hardening Phase Compatibility Matrix (Baseline Jan 4, 2026)

Phase | Core (dspy) | Adapters | O11y | Evals/Optimization | Notes
---|---|---|---|---|---
0 | ✅ | — | — | — | Specs + docs only
1 | ✅ | — | — | — | Subscription lifecycle cleanup
2 | ✅ | — | ✅ | — | Fiber-aware request correlation in LM events
3A | ✅ | ✅ | — | — | Adapter capability interface for structured outputs
3B | ✅ | ✅ | — | — | Structured outputs routing + data_format alignment
4 | ✅ | — | — | — | Deterministic prompt formats
5 | ✅ | — | — | ✅ | Concurrency safety in evals/optimizers
6 | ✅ | — | — | — | Dead code cleanup

Adapters: `dspy-openai`, `dspy-gemini`, `dspy-anthropic`, `dspy-ruby_llm` (plus OpenRouter/Ollama adapters within `dspy-openai`).
O11y: `dspy-o11y`, `dspy-o11y-langfuse`.
Evals/Optimization: `dspy-evals`, `dspy-gepa`, `dspy-miprov2`.

### Registry System

The registry manages:
- Module versions and deployments
- Signature definitions
- Optimization configurations
- Runtime metrics and statistics

Design principles:
- Immutable versioning
- Blue-green deployment support
- Rollback capabilities
- A/B testing support

---

## Testing Architecture

### Test Organization

Tests are organized by type:
- `spec/unit/` - Fast, isolated unit tests
- `spec/integration/` - VCR-recorded integration tests
- `spec/e2e/` - End-to-end tests with real LLM calls

### VCR Strategy

Integration tests use VCR for:
- Consistent test execution
- Reduced API costs
- Faster test runs
- Provider API change detection

Best practices:
- Re-record cassettes periodically
- Skip tests when API keys missing
- Verify successful responses in cassettes
- Use minimal test data for recordings

---

## Future Architecture Considerations

### Planned Improvements

1. **Plugin System**
   - Dynamic provider loading
   - Custom tool registration
   - Extension points for modules

2. **Streaming Support**
   - Server-sent events for real-time responses
   - Progressive rendering in web applications
   - Token-by-token processing

3. **Distributed Execution**
   - Module parallelization
   - Work queue integration
   - Horizontal scaling support

4. **Advanced Caching**
   - Semantic similarity matching
   - Partial result caching
   - Cross-request cache sharing

### Design Principles

As the architecture evolves, these principles guide decisions:
1. **Simplicity over complexity** - Avoid over-engineering
2. **Explicit over implicit** - Clear configuration and behavior
3. **Performance with correctness** - Fast but reliable
4. **Developer experience first** - Easy to use correctly, hard to misuse
5. **Progressive enhancement** - Advanced features are optional
