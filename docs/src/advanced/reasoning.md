---
layout: docs
name: Reasoning Effort & Temperature
description: Configure extended thinking, effort tiers, and sampling for Anthropic models
date: 2026-07-09 00:00:00 +0000
---
# Reasoning Effort & Temperature

Anthropic's newer Claude models (Sonnet 5, Opus 4.7/4.8, Fable 5, Mythos 5, and others) changed how sampling and "thinking" work: some reject a custom `temperature` outright, some default extended thinking to on, and all of them expose a documented `effort` tier independent of thinking. `DSPy::Reasoning` and the `temperature:`/`max_tokens:` constructor options give you a typed way to control this per `DSPy::LM` instance.

**Provider support**: this is currently implemented for the **Anthropic adapter only** (`dspy-anthropic`). Passing `reasoning:` to an OpenAI, Gemini, or Ollama-backed `DSPy::LM` is not supported yet — see [DSPy::LM Migration](https://github.com/vicentereig/dspy.rb/issues/247) for the tracking issue on other providers.

## The problem this solves

Some Claude models reject a non-default `temperature`:

```
400 invalid_request_error: `temperature` is deprecated for this model.
```

Before this feature, `dspy-anthropic` unconditionally sent `temperature: 0.0` and `max_tokens: 4096` on every request, with no way to override either. `DSPy::LM.new(..., temperature: nil)` would even raise `ArgumentError: unknown keyword: :temperature`.

As of this release, the Anthropic adapter:
- Accepts `temperature:` and `max_tokens:` directly.
- Automatically omits `temperature` on models that reject it, even if you never touch `reasoning:`.
- Adds a `reasoning:` option backed by `DSPy::Reasoning`, mapping to Anthropic's `output_config.effort` and `thinking` parameters.

## `DSPy::Reasoning`

`DSPy::Reasoning` is a typed, provider-agnostic value object. Exactly one mode is set per instance:

```ruby
DSPy::Reasoning.low      # output_config.effort: "low"
DSPy::Reasoning.medium   # output_config.effort: "medium"
DSPy::Reasoning.high     # output_config.effort: "high"
DSPy::Reasoning.xhigh    # output_config.effort: "xhigh"
DSPy::Reasoning.max      # output_config.effort: "max"
DSPy::Reasoning.budget(8_000) # thinking: { type: "enabled", budget_tokens: 8_000 }
DSPy::Reasoning.adaptive       # thinking: { type: "adaptive" }
DSPy::Reasoning.disabled       # thinking: { type: "disabled" }
```

Pass it to `DSPy::LM.new`:

```ruby
lm = DSPy::LM.new(
  "anthropic/claude-sonnet-5",
  api_key: ENV["ANTHROPIC_API_KEY"],
  reasoning: DSPy::Reasoning.high
)

DSPy.configure { |c| c.lm = lm }
```

`.max` is not part of Anthropic's originally-sketched effort tiers in the tracking issue; it's included because Anthropic documents it as a real `output_config.effort` value.

### Effort tiers vs. extended thinking

Effort (`.low`/`.medium`/`.high`/`.xhigh`/`.max`) and extended thinking (`.budget`/`.adaptive`/`.disabled`) are independent Anthropic features. `DSPy::Reasoning` only lets you set one *or* the other per value — you can't construct a single `DSPy::Reasoning` that means "effort: high AND a manual thinking budget." If you need both, that's a real limitation of the current API; please open an issue if it blocks you.

That said, on **opt-in-adaptive model families** (Opus 4.7/4.8, Opus/Sonnet 4.6), the adapter automatically adds `thinking: { type: "adaptive" }` whenever you pass an effort tier. Anthropic's docs are explicit that these models run *without* thinking unless that flag is set, independent of `output_config.effort` — so without this, `DSPy::Reasoning.high` on Opus 4.8 would silently change token spend without engaging the model's actual reasoning. On models where thinking is already on by default (Sonnet 5) or always on (Fable 5, Mythos 5), or where adaptive thinking isn't available at all (Opus 4.5), effort tiers are sent as-is with no implicit `thinking` param.

### Model support varies by family

Not every Claude model supports every `DSPy::Reasoning` mode. The adapter validates your choice against the model at `DSPy::LM.new` construction time and raises `DSPy::LM::ConfigurationError` immediately if it's unsupported — you don't have to wait for a request to fail:

```ruby
DSPy::LM.new(
  "anthropic/claude-sonnet-5",
  api_key: ENV["ANTHROPIC_API_KEY"],
  reasoning: DSPy::Reasoning.budget(2_000)
)
# => DSPy::LM::ConfigurationError: claude-sonnet-5 does not support manual thinking
#    budgets (DSPy::Reasoning.budget). This model only supports adaptive thinking;
#    use DSPy::Reasoning.adaptive or an effort tier instead.
```

Roughly:
- **Sonnet 5, Opus 4.7/4.8, Fable 5, Mythos 5** — adaptive thinking only (no manual `budget_tokens`); full effort tier support including `xhigh`/`max`.
- **Opus/Sonnet 4.6** — manual `budget_tokens` still accepted (deprecated by Anthropic) or opt-in adaptive; effort tiers up to `max`, but not `xhigh`.
- **Opus 4.5** — manual `budget_tokens` only, no adaptive thinking; effort tiers up to `high` only.
- **Models not recognized by this gem** (including future Anthropic releases not yet added) fall back to classic behavior: manual `budget_tokens` only, no effort tiers at all. `DSPy::Reasoning.low` on such a model raises `ConfigurationError` rather than silently guessing.

`DSPy::Reasoning.budget(n)` also validates `1024 <= n < max_tokens`, matching Anthropic's documented minimum and the API's own `budget_tokens < max_tokens` requirement.

## `temperature`

`temperature:` now has three distinct states:

```ruby
DSPy::LM.new("anthropic/claude-sonnet-5", api_key: key)
# not passed: omitted automatically for models that reject it,
# or when reasoning: makes extended thinking active; otherwise 0.0

DSPy::LM.new("anthropic/claude-sonnet-5", api_key: key, temperature: nil)
# always omitted from the request, regardless of model

DSPy::LM.new("anthropic/claude-sonnet-5", api_key: key, temperature: 0.7)
# always sent as-is, regardless of model (the API may reject it with a 400
# if the model truly can't take it — DSPy doesn't second-guess an explicit value)
```

If you never pass `temperature:` or `reasoning:` at all, existing code keeps working exactly as before on models that don't have this restriction (`temperature: 0.0` is still sent). The fix is entirely about *not* sending an incompatible default — it does not change behavior for classic models.

## `max_tokens`

`max_tokens:` is a regular constructor option, defaulting to `4096`:

```ruby
DSPy::LM.new(
  "anthropic/claude-opus-4-6",
  api_key: ENV["ANTHROPIC_API_KEY"],
  max_tokens: 16_384,
  reasoning: DSPy::Reasoning.budget(8_000)
)
```

Increase it when using `DSPy::Reasoning.budget(n)` with a large token budget, since Anthropic requires `budget_tokens < max_tokens`. Note that `.budget(n)` requires a model where manual thinking budgets are still supported (e.g. Opus/Sonnet 4.6); newer models like Opus 4.7/4.8 or Sonnet 5 are adaptive-only and reject manual budgets — use `DSPy::Reasoning.adaptive` or an effort tier on those instead.

## Structured outputs compose with reasoning

Effort and structured-output schemas share a single `output_config` request parameter under the hood — `reasoning:` works alongside `structured_outputs: true` (the default) without any extra configuration:

```ruby
lm = DSPy::LM.new(
  "anthropic/claude-opus-4-8",
  api_key: ENV["ANTHROPIC_API_KEY"],
  reasoning: DSPy::Reasoning.high,
  structured_outputs: true # default
)
```
