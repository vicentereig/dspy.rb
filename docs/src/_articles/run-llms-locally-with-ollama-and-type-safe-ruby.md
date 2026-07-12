---
layout: blog
title: "Run LLMs Locally with Ollama and Typed Ruby"
description: "Connect DSPy.rb to Ollama's OpenAI-compatible endpoint and validate local model output against Ruby signatures."
date: 2025-07-28
author: "Vicente Reig"
category: "Features"
reading_time: "2 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/run-llms-locally-with-ollama-and-type-safe-ruby/"
image: /images/og/run-llms-locally-with-ollama-and-type-safe-ruby.png
---

DSPy.rb v0.15.0 added an Ollama adapter. It points the OpenAI client at Ollama's compatible `/v1` endpoint, so the same signature and module APIs can run against a model on your machine.

Local inference removes per-request API charges. It does not make compute free, guarantee privacy for the rest of your application, or make a small model behave like the cloud model you replace. Evaluate the model you intend to use.

## Start Ollama

Install Ollama using its [current installation instructions](https://ollama.com/download), then pull and run a model:

```bash
ollama pull llama3.2
ollama serve
```

Add DSPy.rb's OpenAI adapter gem:

```ruby
gem "dspy"
gem "dspy-openai"
```

The `ollama/` provider prefix selects `OllamaAdapter`:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new("ollama/llama3.2")
end
```

Local Ollama does not require an API key. The adapter uses `http://localhost:11434/v1` unless you pass another `base_url`.

## Validate Structured Results

```ruby
class Category < T::Enum
  enums do
    Hardware = new("hardware")
    Software = new("software")
    Service = new("service")
  end
end

class ProductAnalysis < DSPy::Signature
  input do
    const :name, String
    const :description, String
  end

  output do
    const :category, Category
    const :features, T::Array[String]
    const :summary, String
  end
end

analysis = DSPy::Predict.new(ProductAnalysis).call(
  name: "Mechanical Keyboard",
  description: "A hot-swappable keyboard with tactile switches"
)

puts analysis.category.serialize
puts analysis.features.inspect
```

DSPy.rb asks for structured output, extracts JSON, and coerces the result into the signature's declared types. A model can still return invalid or factually poor data. Validation rejects incompatible structure; evaluation determines whether the program solves the task.

## Structured-Output Compatibility

Ollama models differ in how well they follow an OpenAI-style response schema. The adapter first uses the configured structured-output path. If Ollama rejects `response_format`, it retries that request with DSPy.rb's prompt-based JSON path.

That fallback is narrow. It does not retry arbitrary failures, and prompt-based JSON still depends on the model following instructions.

You can disable native structured output explicitly:

```ruby
lm = DSPy::LM.new(
  "ollama/llama3.2",
  structured_outputs: false
)
```

## Remote Ollama

Pass `base_url` for another server:

```ruby
lm = DSPy::LM.new(
  "ollama/llama3.2",
  base_url: "https://ollama.internal.example/v1",
  api_key: ENV.fetch("OLLAMA_API_KEY")
)
```

The adapter requires a non-empty key for a non-local URL because the OpenAI client and protected deployments commonly expect one. Authentication behavior ultimately belongs to the server in front of Ollama.

## Switching Models by Environment

The signature can stay fixed while configuration chooses a provider:

```ruby
model_id = ENV.fetch("DSPY_MODEL", "ollama/llama3.2")

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    model_id,
    api_key: ENV["OPENAI_API_KEY"]
  )
end
```

The call site remains the same. The behavior will not. Keep provider-specific evaluation results, latency measurements, and resource requirements with each deployment candidate.

## Local Development Checks

- Pin the Ollama model name and tag rather than relying on whatever is installed.
- Record representative tests with VCR when CI cannot run Ollama.
- Measure latency on the hardware that will serve the model.
- Do not send sensitive inputs to logs or traces merely because inference is local.
- Re-run evaluation before replacing a local model with a cloud model, or the reverse.

Ollama gives DSPy.rb another execution target. Ruby still owns the program, and the signature still defines the boundary the result must cross.
