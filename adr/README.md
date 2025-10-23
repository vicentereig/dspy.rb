# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the DSPy.rb project.

## What is an ADR?

An Architecture Decision Record (ADR) is a document that captures an important architectural decision made along with its context and consequences.

## Format

Each ADR is a markdown file with a descriptive name. ADRs are numbered sequentially and include:

- **Status**: Draft, Proposed, Accepted, Deprecated, Superseded
- **Context**: What is the issue that we're seeing that is motivating this decision?
- **Decision**: What is the change that we're proposing and/or doing?
- **Consequences**: What becomes easier or more difficult to do because of this change?

## Index

| ADR | Title | Status | Date | Summary |
|-----|-------|--------|------|---------|
| [001](001-prediction-type-conversion-design.md) | DSPy::Prediction Type Conversion Design | Accepted | 2025-01-20 | Analysis of design patterns for the Prediction class type conversion system |
| [002](002-prediction-refactoring-recommendation.md) | DSPy::Prediction Refactoring Recommendation | Accepted | 2025-01-20 | Decision to keep current implementation with minor improvements |
| [003](003-ruby-idiomatic-api-design.md) | Ruby-Idiomatic API Design | Accepted | 2025-07-20 | Core design decisions for making DSPy.rb feel naturally Ruby |
| [004](004-single-field-union-types.md) | Single-Field Union Types with Automatic Type Detection | Proposed | 2025-07-21 | Automatic type detection for union types using class names, eliminating boilerplate |
| [005](005-multi-method-tool-system.md) | Multi-Method Tool System (Toolsets) | Proposed | 2025-07-21 | Support for exposing multiple methods from a single class as individual tools |
| [006](006-unified-image-type-vs-provider-specific-types.md) | Unified Image Type vs. Provider-Specific Types | Accepted | 2025-08-02 | Decision on handling multimodal image inputs across different LLM providers |
| [007](007-observability-event-interception-architecture.md) | Observability Event Interception Architecture | Accepted | 2025-08-12 | Event-based observability system for tracing and monitoring |
| [008](008-miprov2-analysis.md) | MIPROv2 Python Implementation Analysis | In Progress | 2025-10-13 | Analysis and implementation notes for MIPROv2 optimizer |
| [009](009-gepa-telemetry-phase0.md) | GEPA Telemetry Phase 0 Plan | Accepted | 2025-10-19 | Initial telemetry system for GEPA optimizer |
| [010](010-miprov2-packaging.md) | MIPROv2 Packaging | Accepted | 2025-10-21 | Packaging strategy for MIPROv2 gem with native dependencies |
| [011](011-ci-matrix-bundler-caching.md) | CI Matrix Bundler Caching Strategy | Accepted | 2025-10-23 | Solution for bundler caching conflicts in GitHub Actions matrix builds |

## Creating a New ADR

When making significant architectural decisions:

1. Create a new file: `XXX-short-description.md` (where XXX is the next number)
2. Include Status, Context, Decision, and Consequences sections
3. Link it in this README
4. Commit with a descriptive message

## References

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) by Michael Nygard
- [ADR Tools](https://github.com/npryce/adr-tools) - Command-line tools for working with ADRs