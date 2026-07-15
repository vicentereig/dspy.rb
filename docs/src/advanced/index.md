---
layout: docs
title: Advanced Topics
description: Explore advanced patterns and techniques in DSPy.rb
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-07-11 00:00:00 +0000
---
# Advanced Topics

These guides cover extension points after you can define a signature and run a module. For ordinary composition, retrieval, multimodal inputs, or agents, start from [Build](/dspy.rb/build/). For runtime integration and deployment concerns, use [Operate](/dspy.rb/production/).

## Advanced Guides

### [Custom Toolsets](./custom-toolsets/)
Extend the baseline Toolset DSL with bounded application operations.

### [Rich Types](./complex-types/)
Work with structured data, nested objects, and rich type hierarchies in your signatures.

### [Package and Adapter Paths](/dspy.rb/getting-started/packages/)
Choose the package that owns an adapter or optional subsystem, then keep package-specific setup and caveats in its linked package guide. General provider selection remains in [Installation](/dspy.rb/getting-started/installation/).

### [Module Runtime Context](./module-runtime-context/)
Control language-model resolution and propagation when an integration needs call-scoped behavior. Add cross-cutting call behavior in [Module Lifecycle Callbacks](./module-lifecycle-callbacks/).

The complete generated surface remains available in [llms-full.txt](/dspy.rb/llms-full.txt) when you need a single reference document.
