---
layout: blog
title: "Rich Signatures, Lean Schemas"
date: 2025-10-07
description: "When signatures hit 5+ fields, JSON Schema overhead eats hundreds of tokens per call. BAML keeps them compact—no retraining needed."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/baml-schema-format/"
image: /images/og/baml-schema-format.png
---

# Rich Signatures, Lean Schemas

I find writing Signatures instead of Prompts similar to modeling databases with ActiveRecord. You use objects to model the world as you want your prompt to see it. Start simple, add complexity as needed, and the framework handles the details.

## Starting Simple

Here's a basic signature - just input and output:

```ruby
class SentimentAnalysis < DSPy::Signature
  input do
    const :text, String
  end
  output do
    const :sentiment, String, description: "positive, negative, or neutral"
  end
end
```

Clean. Minimal. The LM receives a compact schema that fits in a few lines.

## Signatures Get Richer

But real applications need more structure. Task decomposition, for example:

```ruby
class TaskDecomposition < DSPy::Signature
  description "Autonomously analyze a research topic and define optimal subtasks"

  input do
    const :topic, String, description: "The main research topic to investigate"
    const :context, String, description: "Any additional context or constraints"
  end

  output do
    const :subtasks, T::Array[String], description: "Research subtasks with clear objectives"
    const :task_types, T::Array[String], description: "Type classification for each task"
    const :priority_order, T::Array[Integer], description: "Priority rankings (1-5 scale)"
    const :estimated_effort, T::Array[Integer], description: "Effort estimates in hours"
    const :dependencies, T::Array[String], description: "Task dependency relationships"
    const :agent_requirements, T::Array[String], description: "Suggested agent types/skills"
  end
end
```

Six output fields with descriptions. Nested types. This is where schemas start creeping into your prompts.

## The Schema Problem

With Enhanced Prompting (the default mode in DSPy.rb), schemas are embedded directly in prompts. Here's what the LM actually receives for `TaskDecomposition`:

```json
{
  "$schema": "http://json-schema.org/draft-06/schema#",
  "type": "object",
  "properties": {
    "subtasks": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Research subtasks with clear objectives"
    },
    "task_types": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Type classification for each task"
    },
    "priority_order": {
      "type": "array",
      "items": {"type": "integer"},
      "description": "Priority rankings (1-5 scale)"
    },
    "estimated_effort": {
      "type": "array",
      "items": {"type": "integer"},
      "description": "Effort estimates in hours"
    },
    "dependencies": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Task dependency relationships"
    },
    "agent_requirements": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Suggested agent types/skills"
    }
  },
  "required": ["subtasks", "task_types", "priority_order", "estimated_effort", "dependencies", "agent_requirements"]
}
```

**1,378 characters. ~345 tokens. Every. Single. Call.**

For rich signatures, JSON Schema verbosity becomes a real cost. Each API call carries hundreds of tokens just describing the output structure.

## BAML: The Simple Fix

[DSPy.rb v0.28.2](https://github.com/vicentereig/dspy.rb) adds [BAML](https://github.com/vicentereig/sorbet-baml) schema format support via the [`sorbet-baml`](https://github.com/vicentereig/sorbet-baml) gem. BAML provides the same information compactly:

```baml
class TaskDecomposition {
  subtasks string[]
  task_types string[]
  priority_order int[]
  estimated_effort int[]
  dependencies string[]
  agent_requirements string[]
}
```

**200 characters. ~50 tokens. 85.5% savings.**

Same structure. Same type safety. Same validation. But 295 fewer tokens per call.

## Verified Performance

From our [integration tests](https://github.com/vicentereig/dspy.rb/blob/main/spec/integration/baml_schema_format_spec.rb) across multiple signatures:

**TaskDecomposition (6 fields):**
- JSON: 1,378 chars (~345 tokens)
- BAML: 200 chars (~50 tokens)
- **Savings: 85.5% (~295 tokens/call)**

**ResearchExecution (6 fields):**
- JSON: 1,148 chars (~287 tokens)
- BAML: 195 chars (~49 tokens)
- **Savings: 83.0% (~238 tokens/call)**

**Aggregate across all tests:**
- JSON: 2,526 chars (~632 tokens)
- BAML: 395 chars (~99 tokens)
- **Savings: 84.4% (~533 tokens/call)**

Quality: 100% identical outputs across all tests.

No training needed. No optimization required. Your baseline signatures just got more efficient.

## How to Use

One configuration change:

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    schema_format: :baml
  )
end

# Use any signature - BAML is automatic
predictor = DSPy::Predict.new(TaskDecomposition)
result = predictor.call(
  topic: "Build user authentication",
  context: "Focus on security best practices"
)
```

Works with all providers in Enhanced Prompting mode: OpenAI, Anthropic, Gemini, Ollama.

## When It Matters

BAML shines with:
- **Complex signatures** (5+ fields, nested types)
- **High-volume applications** (the savings compound)
- **Cost-sensitive projects** (every token counts)

For simple 1-3 field signatures, the difference is negligible.

If you're using OpenAI's Structured Outputs mode (`structured_outputs: true`), schemas are sent via API instead of in prompts - BAML has no effect there since schemas never appear in the prompt.

## Requirements

The [`sorbet-baml`](https://github.com/vicentereig/sorbet-baml) gem is automatically included with DSPy.rb:

```ruby
# Gemfile
gem 'dspy'
```

BAML generation is automatic from your Sorbet type signatures - no additional setup needed.

## Resources

- [Schema Formats Documentation](https://vicentereig.github.io/dspy.rb/core-concepts/signatures/#schema-formats)
- [Rich Types Guide](https://vicentereig.github.io/dspy.rb/advanced/complex-types/#schema-format-options)
- [Getting Started](https://vicentereig.github.io/dspy.rb/getting-started/quick-start/)
- [DSPy.rb GitHub](https://github.com/vicentereig/dspy.rb)
- [Integration Tests](https://github.com/vicentereig/dspy.rb/blob/main/spec/integration/baml_schema_format_spec.rb)
