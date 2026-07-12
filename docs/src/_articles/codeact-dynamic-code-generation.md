---
layout: blog
title: "CodeAct: Dynamic Code Generation"
description: "CodeAct is a tool-using agent loop that generates and executes Ruby code. It ships in the optional dspy-code_act gem."
date: 2025-07-11 00:00:00 +0000
last_modified_at: 2025-10-07 00:00:00 +0000
category: Article
---
# CodeAct documentation moved

CodeAct now lives in the optional `dspy-code_act` gem. The agent lets a model choose and execute Ruby code over several bounded iterations; it is separate from DSPy.rb core because generated-code execution needs a different safety boundary from ordinary prediction.

- Install: `gem 'dspy-code_act', '~> 0.29'`
- Read the [CodeAct documentation](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/code_act/README.md).
- Inspect the [implementation](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/code_act.rb).

The current implementation evaluates generated Ruby in the application process. Use it for controlled experiments unless you provide process or container isolation.
