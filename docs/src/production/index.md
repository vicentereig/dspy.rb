---
layout: docs
title: Production Guide
description: Deploy and operate DSPy.rb applications in production
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-07-20 00:00:00 +0000
---
# Production Guide

Production applications need explicit ownership of artifacts, telemetry, failures, secrets, and provider budgets. DSPy.rb supplies storage, registry, and observability components; the application still owns deployment policy and recovery.

## Choose an Operational Concern

### [Events](/dspy.rb/core-concepts/events/)
Subscribe to typed runtime events for application integrations.

### [Module Runtime Context](/dspy.rb/advanced/module-runtime-context/)
Scope language-model selection and propagation across module calls.

### [Module Lifecycle Callbacks](/dspy.rb/advanced/module-lifecycle-callbacks/)
Add ordered before, around, and after behavior to a module call.

### [Concurrent Predictions](/dspy.rb/advanced/concurrent-predictions/)
Join independent predictor calls under an explicit failure policy and measured limit.

### [Interception and Monkey-Patching](/dspy.rb/advanced/observability-interception/)
Prefer supported event interception and identify the narrow cases where a monkey patch remains necessary.

### [Rails](/dspy.rb/advanced/rails-integration/)
Place DSPy.rb configuration and calls within Rails services, jobs, caching, and instrumentation.

### [Storage](./storage/)
Persist optimized programs and their metadata with the storage API.

### [Registry](./registry/)
Register and promote versioned program artifacts across environments.

### [Observability](./observability/)
Export module, LM, tool, and optimizer telemetry through OpenTelemetry.

### [Score Reporting](./score-reporting/)
Create typed evaluation scores and bound asynchronous Langfuse delivery.

### [Troubleshooting](./troubleshooting/)
Diagnose configuration, provider, parsing, dependency, and test failures.

## Assign Application Ownership

### Performance
- Measure latency and token usage before changing models or concurrency
- Cache only operations whose inputs and invalidation rules are explicit
- Move non-critical application work to background jobs

### Reliability
- Define retry and timeout policy at the application and provider-SDK boundaries
- Bound agent iterations and tool side effects
- Test fallbacks against the failures they are meant to handle

### Security
- Never log sensitive data or API keys
- Implement rate limiting
- Use environment-specific configurations

### Cost Management
- Monitor token usage per operation
- Implement usage quotas
- Cache expensive operations

## Deployment Checklist

- [ ] Environment variables configured
- [ ] Logging and monitoring set up
- [ ] Error handling implemented
- [ ] Caching strategy defined
- [ ] Performance benchmarks established
- [ ] Cost monitoring enabled
- [ ] Backup and recovery procedures
