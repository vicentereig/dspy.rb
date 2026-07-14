---
layout: docs
published: false
title: 'CodeAct: Dynamic Code Generation'
description: 'CodeAct now ships as its own gem with dedicated documentation.'
date: 2025-07-11 00:00:00 +0000
last_modified_at: 2025-10-07 00:00:00 +0000
---
# CodeAct has moved

CodeAct is now packaged as the [`dspy-code_act`](https://github.com/vicentereig/dspy.rb/tree/main/lib/dspy/code_act) gem. The module no longer ships with the core `dspy` gem and has its own documentation bundle.

- Install with `gem 'dspy-code_act', '~> 1.0'` alongside `dspy`.
- Review usage, safety guidelines, and advanced examples in `lib/dspy/code_act/README.md`.
- GitHub Actions run the CodeAct specs separately from the DSPy core suite.

Update old bookmarks to the README inside the gem. CodeAct runs a model-directed code loop; the host application must provide the executor, isolation, permissions, and limits around that loop.
