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

1. [DSPy::Prediction Type Conversion Design](001-prediction-type-conversion-design.md) - Analysis of design patterns for the Prediction class type conversion system
2. [DSPy::Prediction Refactoring Recommendation](002-prediction-refactoring-recommendation.md) - Decision to keep current implementation with minor improvements
3. [Ruby-Idiomatic API Design](003-ruby-idiomatic-api-design.md) - Core design decisions for making DSPy.rb feel naturally Ruby

## Creating a New ADR

When making significant architectural decisions:

1. Create a new file: `XXX-short-description.md` (where XXX is the next number)
2. Include Status, Context, Decision, and Consequences sections
3. Link it in this README
4. Commit with a descriptive message

## References

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) by Michael Nygard
- [ADR Tools](https://github.com/npryce/adr-tools) - Command-line tools for working with ADRs