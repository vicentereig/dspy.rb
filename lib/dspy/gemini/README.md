# DSPy Gemini Adapter

`dspy-gemini` lets `DSPy::LM` call model IDs with the `gemini/` prefix. The package is a supported provider adapter; model and SDK capabilities still vary.

See the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for canonical status and model/SDK boundaries.

## Prerequisites

- Ruby 3.3 or newer and Bundler
- a Gemini API key
- a Gemini model ID available to your account

## Install and Run

Add both gems to your `Gemfile`:

```ruby
gem "dspy"
gem "dspy-gemini"
```

Save this as `gemini_smoke.rb`:

```ruby
require "dspy"

lm = DSPy::LM.new(
  ENV.fetch("GEMINI_MODEL"),
  api_key: ENV.fetch("GEMINI_API_KEY")
)

response = lm.raw_chat([{ role: "user", content: "Reply with: adapter ready" }])
puts response.content
```

Then install and run it:

```bash
bundle install
export GEMINI_API_KEY="your-key"
export GEMINI_MODEL="gemini/your-model-id"
bundle exec ruby gemini_smoke.rb
```

The command prints the model response. Requiring `dspy` loads the installed adapter for a `gemini/` model; explicit `require "dspy/gemini"` is also supported.

## Failure Conditions

- A missing key raises from `ENV.fetch` before the request.
- A missing or incompatible `gemini-ai` dependency prevents the adapter from loading.
- An unavailable model, safety rejection, or invalid request raises an adapter/provider error.
- Schema, image, safety, and streaming behavior depend on the selected Gemini model and SDK/API version. Verify the exact request; installing the gem does not guarantee every capability.
