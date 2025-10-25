---
layout: docs
name: Dependency Tree
description: Understand how the DSPy.rb core gem relates to its sibling packages and optional dependencies.
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Dependency Tree
  url: "/core-concepts/dependency-tree/"
date: 2025-10-25 00:00:00 +0000
---
# Dependency Tree

DSPy.rb now ships as a lightweight core plus a set of sibling gems. Each sibling packages an optional feature set behind an environment toggle so you only install what you need.

## Core Gem

`dspy` depends on:

- `dry-configurable`, `dry-logger`, `async`, `concurrent-ruby`
- Sorbet runtime helpers (`sorbet-runtime`, `sorbet-schema`, `sorbet-baml`)
- Built-in tools and memory layers

Everything else is loaded via `begin … rescue LoadError` so missing siblings fail with actionable messages.

## Stable Siblings

| Gem | What It Provides | Version |
| --- | --- | --- |
| `dspy-schema` | `DSPy::TypeSystem::SorbetJsonSchema` for downstream reuse. | 1.0.0 |
| `dspy-o11y` | `DSPy::Observability`, async span processor, observation types. | 1.0.0 |
| `dspy-o11y-langfuse` | Langfuse/OpenTelemetry auto configuration and SSL patches. | 1.0.0 |

Install via:

```ruby
gem 'dspy'
gem 'dspy-o11y'
gem 'dspy-o11y-langfuse'
```

Or, inside this monorepo:

```bash
DSPY_WITH_O11Y=1 DSPY_WITH_O11Y_LANGFUSE=1 bundle install
```

## Preview Siblings

| Gem | Purpose | Notes |
| --- | --- | --- |
| `dspy-code_act` | Think-Code-Observe agents, REPL execution sandbox. | 0.x interface subject to change. |
| `dspy-datasets` | Dataset loaders, Parquet/Arrow helpers. | Requires optional Arrow deps in CI. |
| `dspy-evals` | High-throughput metrics + regression fixtures. | Ships only where needed. |
| `dspy-miprov2` | Bayesian optimizer, Gaussian Process backend. | Pulls BLAS/LAPACK via `numo-*`. |
| `dspy-gepa` | GEPA teleprompter integration (depends on `gepa`). | `DSPy_WITH_GEPA` toggles install. |
| `gepa` | Optimizer core shared by DSPy and ADE demos. | Still versioned with DSPy. |

## Upcoming Work

- **Provider adapters**: `openai`, `anthropic`, and `gemini-ai` remain bundled in the core gem for now. Future work will split each adapter into its own optional gem so you can choose only the SDKs you need.
- **New Relic observability**: `dspy-o11y-newrelic` will mirror the Langfuse adapter once New Relic instrumentation stabilizes.

Track progress in `adr/012-modular-sibling-gems-roadmap.md` and Issue #102.
