---
layout: blog
title: "BAML Schema Format: 84%+ Token Savings"
date: 2025-10-07
description: "BAML schema format reduces prompt tokens by 84% in Enhanced Prompting mode"
author: "DSPy.rb Team"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/baml-schema-format/"
image: /images/og/baml-schema-format.png
---

# BAML Schema Format: 84%+ Token Savings

DSPy.rb v0.28.2 adds [BAML](https://docs.boundaryml.com) schema format support - a compact alternative to JSON Schema that saves 84%+ prompt tokens in Enhanced Prompting mode.

## Enhanced Prompting vs Structured Outputs

**BAML applies only to Enhanced Prompting mode** (`structured_outputs: false`), where schemas are embedded in prompts:

```ruby
# Enhanced Prompting - BAML saves 84%+ tokens
lm = DSPy::LM.new(
  'openai/gpt-4o-mini',
  structured_outputs: false,  # Schema in prompt
  schema_format: :baml        # Use compact format
)
```

With `structured_outputs: true`, OpenAI receives JSON Schema via API - the schema never appears in the prompt, so BAML has no effect.

## The Problem

JSON schemas are verbose. Example output schema:

```json
{
  "$schema": "http://json-schema.org/draft-06/schema#",
  "type": "object",
  "properties": {
    "subtasks": {
      "type": "array",
      "items": {"type": "string"}
    },
    "task_types": {
      "type": "array",
      "items": {"type": "string"}
    },
    "priority_order": {
      "type": "array",
      "items": {"type": "integer"}
    }
  },
  "required": ["subtasks", "task_types", "priority_order"]
}
```

**1,378 characters (~345 tokens)**

## The Solution

BAML provides the same information compactly:

```baml
class TaskDecompositionOutput {
  subtasks string[]
  task_types string[]
  priority_order int[]
}
```

**200 characters (~50 tokens)**

**Savings: 85.5% fewer tokens**

## How to Use

Configure globally:

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    schema_format: :baml
  )
end

# Use any signature - BAML is automatic
predictor = DSPy::Predict.new(YourSignature)
result = predictor.call(input: "...")
```

Or per-signature:

```ruby
prompt = DSPy::Prompt.from_signature(
  YourSignature,
  schema_format: :baml
)
```

## Verified Performance

From [integration tests](https://github.com/vicentereig/dspy.rb/blob/main/spec/integration/baml_schema_format_spec.rb):

**TaskDecomposition (6 fields):**
- JSON: 1,378 chars (~345 tokens)
- BAML: 200 chars (~50 tokens)
- Savings: **85.5% (~295 tokens/call)**

**ResearchExecution (6 fields):**
- JSON: 1,148 chars (~287 tokens)
- BAML: 195 chars (~49 tokens)
- Savings: **83.0% (~238 tokens/call)**

**Aggregate:**
- JSON: 2,526 chars (~632 tokens)
- BAML: 395 chars (~99 tokens)
- Savings: **84.4% (~533 tokens/call)**

Quality: 100% identical outputs across all tests.

## When to Use BAML

**Use BAML when:**
- Complex signatures (5+ fields)
- Enhanced Prompting mode (`structured_outputs: false`)
- High API call volumes
- Cost-sensitive applications

**Stick with JSON when:**
- Simple signatures (1-3 fields)
- Structured Outputs mode (`structured_outputs: true`)
- Legacy compatibility needed

## Provider Support

Works with all providers in Enhanced Prompting mode:

```ruby
# OpenAI
DSPy::LM.new('openai/gpt-4o-mini', schema_format: :baml)

# Anthropic
DSPy::LM.new('anthropic/claude-sonnet-4-5', schema_format: :baml)

# Google Gemini
DSPy::LM.new('gemini/gemini-2.5-pro', schema_format: :baml)

# Ollama (local)
DSPy::LM.new('ollama/llama3.2', schema_format: :baml)
```

## Requirements

[`sorbet-baml`](https://github.com/maxveldink/sorbet-baml) gem (automatically included with `dspy-rb`):

```ruby
# Gemfile
gem 'dspy-rb'
```

No additional setup needed - BAML generation is automatic from your Sorbet types.

## Resources

- [Schema Formats Documentation](https://vicentereig.github.io/dspy.rb/core-concepts/signatures/#schema-formats)
- [Complex Types Guide](https://vicentereig.github.io/dspy.rb/advanced/complex-types/#schema-format-options)
- [Getting Started](https://vicentereig.github.io/dspy.rb/getting-started/quick-start/)
- [DSPy.rb GitHub](https://github.com/vicentereig/dspy.rb)
- [Integration Tests](https://github.com/vicentereig/dspy.rb/blob/main/spec/integration/baml_schema_format_spec.rb)
- [OpenAI Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs) (comparison)
