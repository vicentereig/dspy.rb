# DSPy OpenAI-Compatible Adapter

`dspy-openai` provides the adapters selected by `openai/`, `openrouter/`, and `ollama/` model prefixes. It is a supported provider package, not a promise that those endpoints expose identical capabilities.

See [Installation and Provider Setup](https://oss.vicente.services/dspy.rb/getting-started/installation/) for provider selection and the [package matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for canonical status and model/SDK boundaries.

## Prerequisites

- Ruby 3.3 or newer and Bundler
- an endpoint and model compatible with the selected prefix
- provider credentials when the endpoint requires them

## Install and Run

Add both gems to your `Gemfile`:

```ruby
gem "dspy"
gem "dspy-openai"
```

Save this as `openai_compatible_smoke.rb`:

```ruby
require "dspy"

lm = DSPy::LM.new(
  ENV.fetch("DSPY_MODEL"),
  api_key: ENV["DSPY_API_KEY"]
)

response = lm.raw_chat([{ role: "user", content: "Reply with: adapter ready" }])
puts response.content
```

Then install and run it:

```bash
bundle install
export DSPY_MODEL="openai/your-model-id"
export DSPY_API_KEY="your-key"
bundle exec ruby openai_compatible_smoke.rb
```

The command prints the endpoint's response. Use an `openrouter/...` model and OpenRouter key for OpenRouter, or an `ollama/...` model with the locally required authentication and endpoint setup for Ollama.

## Failure Conditions

- A missing `DSPY_MODEL` raises before the request; a missing key fails when the chosen endpoint requires one.
- A missing or incompatible official `openai` SDK, or the conflicting older `ruby-openai` gem, prevents the adapter from loading.
- Model names, request options, structured output, streaming, images, and fallback behavior vary by model and compatible endpoint.
- A provider prefix selects an adapter. It does not establish that the selected model supports a feature. Test the exact model, endpoint, SDK version, and request options.
