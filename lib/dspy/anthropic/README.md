# DSPy Anthropic Adapter

`dspy-anthropic` lets `DSPy::LM` call model IDs with the `anthropic/` prefix. The package is a supported provider adapter; model and API-version capabilities still vary.

See the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for canonical status and model/SDK boundaries.

## Prerequisites

- Ruby 3.3 or newer and Bundler
- an Anthropic API key
- an Anthropic model ID available to your account

## Install and Run

Add both gems to your `Gemfile`:

```ruby
gem "dspy"
gem "dspy-anthropic"
```

Save this as `anthropic_smoke.rb`:

```ruby
require "dspy"

lm = DSPy::LM.new(
  ENV.fetch("ANTHROPIC_MODEL"),
  api_key: ENV.fetch("ANTHROPIC_API_KEY")
)

response = lm.raw_chat([{ role: "user", content: "Reply with: adapter ready" }])
puts response.content
```

Then install and run it:

```bash
bundle install
export ANTHROPIC_API_KEY="your-key"
export ANTHROPIC_MODEL="anthropic/your-model-id"
bundle exec ruby anthropic_smoke.rb
```

The command prints the model response. Requiring `dspy` loads the installed adapter for an `anthropic/` model; explicit `require "dspy/anthropic"` is also supported.

## Failure Conditions

- A missing key raises from `ENV.fetch` before the request.
- A missing or incompatible Anthropic SDK prevents the adapter from loading.
- An unavailable model or rejected request raises an adapter/provider error.
- Structured output, tools, images, documents, and streaming depend on the selected model and Anthropic API version. Verify the exact request; installing the gem does not guarantee every capability.
