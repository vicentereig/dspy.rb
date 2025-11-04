# DSPy Gemini adapter gem

`dspy-gemini` provides the Gemini adapter for DSPy.rb so we can rely on Google's API without bloating the core gem. Install it whenever you plan to call `gemini/*` model ids from DSPy.

## When you need it
- You call `DSPy::LM.new` with a provider of `gemini`.
- You want structured outputs, multimodal prompts, or streaming responses backed by Gemini's Generative Language API.

Projects that only target OpenAI, Anthropic, or other providers can skip this gem.

## Installation
Add it beside `dspy` and install dependencies:

```ruby
# Gemfile
gem 'dspy'
gem 'dspy-gemini'
```

```sh
bundle install
```

The adapter enforces `gemini-ai ~> 4.3` at runtime (and raises if the dependency is missing or out of range).

## Configuration
- Set `ENV['GEMINI_API_KEY']`, or pass `api_key:` directly.

## Basic usage

```ruby
require 'dspy'
# No need to explicitly require 'dspy/gemini'

lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV.fetch('GEMINI_API_KEY'))

```
