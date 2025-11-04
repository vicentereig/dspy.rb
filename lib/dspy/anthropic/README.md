# DSPy Anthropic adapter gem

`dspy-anthropic` provides the Claude adapter for DSPy.rb so we can rely on Anthropic's API without bloating the core gem. Install it whenever you plan to call `anthropic/*` model ids from DSPy.

## When you need it
- You initialize `DSPy::LM` with an Anthropic provider (e.g. `anthropic/claude-3.5-sonnet`).
- You want Claude's structured output helpers, tool use, or streaming responses.

If your project only targets non-Claude providers you can omit this gem.

## Installation

```ruby
# Gemfile
gem 'dspy'
gem 'dspy-anthropic'
```

```sh
bundle install
```

The adapter verifies that the official `anthropic` Ruby SDK `~> 1.12` is available and will raise if the version is missing or incompatible.

## Configuration
- Set `ENV['ANTHROPIC_API_KEY']`, or pass `api_key:` when constructing the LM.

## Basic usage

```ruby
require 'dspy'
# No need to explicitly require 'dspy/anthropic'

lm = DSPy::LM.new('anthropic/claude-3.5-sonnet', api_key: ENV.fetch('ANTHROPIC_API_KEY'))

```
