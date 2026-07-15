# DSPy RubyLLM Adapter (Preview)

`dspy-ruby_llm` delegates model lookup, provider selection, request transport, and capability discovery to [RubyLLM](https://rubyllm.com). The package is preview: provider coverage is not a uniform capability promise.

See the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for canonical status and the files shared with the core gem.

## Prerequisites

- Ruby, Bundler, and `gem "dspy-ruby_llm"`
- RubyLLM credentials and configuration for the selected provider
- a model ID recognized by RubyLLM, or an explicit `provider:` override

## Install and Run

```ruby
gem "dspy-ruby_llm"
```

Save this as `ruby_llm_smoke.rb`:

```ruby
require "dspy"
require "dspy/ruby_llm"

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY")
end

lm = DSPy::LM.new("ruby_llm/gpt-4o")
response = lm.raw_chat([{ role: "user", content: "Reply with: adapter ready" }])
puts response.content
```

```bash
bundle install
export OPENAI_API_KEY="your-key"
bundle exec ruby ruby_llm_smoke.rb
```

The command prints the provider response. DSPy reuses RubyLLM's global configuration only when the `DSPy::LM` call does not supply `api_key`, `base_url`, `timeout`, or `max_retries` overrides. Supplying any of those options creates a scoped adapter configuration.

For a model absent from RubyLLM's registry, specify the provider explicitly:

```ruby
lm = DSPy::LM.new("ruby_llm/my-model", provider: "ollama")
```

## Capability and Failure Boundaries

- A missing RubyLLM credential or unknown model/provider fails before or during the request.
- Registry data and capability detection vary with the installed RubyLLM version.
- Authentication, attachments, schemas, streaming, retries, and request options vary by underlying provider and model; document input is currently restricted to Anthropic.
- Error mapping preserves a DSPy boundary, but provider-specific details still come from RubyLLM and its SDKs. Test the exact model and request your application will use.
