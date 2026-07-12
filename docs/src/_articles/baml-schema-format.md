---
layout: blog
title: "Rich Signatures, Lean Schemas"
date: 2025-10-07
description: "How BAML reduces schema guidance in DSPy.rb's prompt-based structured-response path."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/baml-schema-format/"
image: /images/og/baml-schema-format.png
---

I find writing signatures instead of prompts similar to modeling databases with Active Record. You model the values the program needs; DSPy.rb renders the provider-facing instructions. As signatures grow, the JSON Schema representation can occupy more of the prompt than the task itself.

Consider a signature with six array outputs:

```ruby
class TaskDecomposition < DSPy::Signature
  description "Analyze a research topic and define subtasks"

  input do
    const :topic, String, description: "The research topic"
    const :context, String, description: "Additional constraints"
  end

  output do
    const :subtasks, T::Array[String], description: "Research subtasks"
    const :task_types, T::Array[String], description: "Type for each task"
    const :priority_order, T::Array[Integer], description: "Priority rankings"
    const :estimated_effort, T::Array[Integer], description: "Effort in hours"
    const :dependencies, T::Array[String], description: "Task dependencies"
    const :agent_requirements, T::Array[String], description: "Required skills"
  end
end
```

In the prompt-based path, DSPy.rb normally renders the input and output definitions as JSON Schema. Set `schema_format: :baml` to render the same signature metadata in BoundaryML's compact schema syntax:

```text
class TaskDecomposition {
  subtasks string[]
  task_types string[]
  priority_order int[]
  estimated_effort int[]
  dependencies string[]
  agent_requirements string[]
}
```

## What Changes

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV.fetch('OPENAI_API_KEY'),
    schema_format: :baml,
    structured_outputs: false
  )
end

predictor = DSPy::Predict.new(TaskDecomposition)
result = predictor.call(
  topic: "Build user authentication",
  context: "Focus on security and Rails integration"
)
```

The signature, predictor call, and prediction conversion stay the same. Only the schema guidance in the prompt changes. The [`sorbet-baml`](https://github.com/vicentereig/sorbet-baml) formatter derives BAML from the Sorbet schema; it does not train or optimize the model.

Provider-native structured output is a different path. When DSPy.rb sends a schema through `response_format`, Gemini's generation configuration, or Anthropic's structured-output fields, the prompt renderer's `schema_format` does not control that provider request.

## Recorded Size Comparison

The integration benchmark recorded these approximate sizes for two six-field signatures:

| Signature | JSON Schema | BAML |
|---|---:|---:|
| TaskDecomposition | 1,378 characters | 664 characters |
| ResearchExecution | 1,148 characters | 584 characters |
| Combined | 2,526 characters | 1,248 characters |

The current integration spec reports a 50.6% character reduction across those two signatures. Character count is not a tokenizer measurement and should not be treated as a fixed per-call saving. Field descriptions, nested types, model tokenizers, and the rest of the rendered prompt change the result.

The tests also verify that both formats describe the same signature fields. They do not prove identical model quality across providers.

## When to Use BAML

BAML is most relevant when:

- the application uses prompt-based structured responses;
- schema guidance is a material part of the request;
- signatures contain enough fields or nesting for JSON Schema verbosity to matter;
- evaluation shows that the selected model follows the compact syntax.

For a small signature, the difference may not matter. For provider-native structured output, choose based on the provider contract rather than prompt size. Measure the rendered request and task metric before making BAML the default.

## Resources

- [Schema Formats Documentation](https://oss.vicente.services/dspy.rb/core-concepts/signatures/#schema-formats)
- [Rich Types Guide](https://oss.vicente.services/dspy.rb/advanced/complex-types/#schema-format-options)
- [Integration Tests](https://github.com/vicentereig/dspy.rb/blob/main/spec/integration/baml_schema_format_spec.rb)
- [Benchmark Source](https://github.com/vicentereig/dspy.rb/blob/main/examples/baml_vs_json_benchmark.rb)
