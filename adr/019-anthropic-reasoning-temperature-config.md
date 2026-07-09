# ADR-019: `DSPy::Reasoning` Config Abstraction & Anthropic `temperature`/`max_tokens` Fix

**Status**: Accepted (implemented)
**Date**: 2026-07-08, revised 2026-07-09
**Author**: Paul (with Claude)
**Related**: [Issue #256](https://github.com/vicentereig/dspy.rb/issues/256), [Issue #247](https://github.com/vicentereig/dspy.rb/issues/247)
**Scope**: Anthropic adapter only, plus a shared `DSPy::Reasoning` value object in the core `dspy` gem. OpenAI is explicitly excluded per maintainer request. Gemini/OpenRouter/RubyLLM mappings from #247 are deferred to follow-up PRs.

## Context

`dspy-anthropic`'s `AnthropicAdapter` hard-coded `temperature: 0.0` and `max_tokens: 4096` on every request, with no constructor option to change either. Newer Anthropic models reject the `temperature` parameter outright when set to a non-default value:

```
400 invalid_request_error: `temperature` is deprecated for this model.
```

Users had no way to work around this:
- `DSPy::LM.new("anthropic/claude-sonnet-5", api_key: ..., temperature: nil)` raised `ArgumentError: unknown keyword: :temperature`, because `AdapterFactory` forwards all extra `DSPy::LM.new` options straight into `AnthropicAdapter#initialize`, which didn't declare a `temperature:` keyword at all.
- There was no equivalent override for `max_tokens` either.

Issue #256 was linked to #247 ("Thinking Mode / Reasoning Effort"), where the maintainer had already sketched a concrete API: a typed `DSPy::Reasoning` value object (`.low`, `.medium`, `.high`, `.xhigh`, `.budget(n)`, `.adaptive`, `.disabled`) passed as `reasoning:` to `DSPy::LM.new`, explicitly rejecting a raw `extra_params:` hash, with a hard requirement that unsupported combinations "fail loudly."

A scope proposal was posted on #256 first. The maintainer's response raised six requirements, all incorporated into the final design below:

1. Anthropic-only scope is fine, but the mapping **must be model-family-aware** — verify against current docs rather than assuming uniform `budget_tokens` behavior across models.
2. `dspy-anthropic` still built requests with the deprecated beta `output_format`/`betas` shape; current SDK/docs prefer `output_config.format`. Since `effort` also lives under `output_config`, reasoning and structured outputs must compose under **one** request shape.
3. RubyLLM support is not required to close #256 (the reported production path is `dspy-anthropic`); acceptable only as a thin, optional, non-inventive add-on later.
4. Leave OpenAI out of this PR entirely, even preparatory work.
5. The default call path (no `reasoning:` passed) must independently stop sending implicit `temperature: 0.0` for affected models — distinguishing not-passed vs. explicit `0.0` vs. explicit `nil`.
6. An ADR was welcomed.

### Doc verification

We fetched and read Anthropic's `adaptive-thinking` and `effort` docs in full, and inspected the `anthropic` Ruby gem (this repo pins `>= 1.28.0, < 2.0`; verified directly against the installed `1.28.0`).

**Anthropic's `effort` parameter is real, documented, and works independently of `thinking`**:

> "The effort parameter can be used with or without extended thinking enabled. When used without thinking, it still controls overall token spend for text responses and tool calls." — Anthropic docs

**`output_format`/`betas` are deprecated in the SDK's own YARD docs** in favor of `output_config.format`. `output_config` (carrying both `format` and `effort`) is accepted directly by the **non-beta** `client.messages.create`/`stream`/`stream_raw` — no beta header or `client.beta.messages` required for structured outputs anymore.

**Confirmed model-family capability matrix** ("fixed sampling" = model rejects non-default `temperature`/`top_p`/`top_k` with a 400):

| Model family | Adaptive thinking | Manual `budget_tokens` | `thinking: disabled` | `effort` (low/med/high) | `effort: xhigh` | `effort: max` | Fixed sampling |
|---|---|---|---|---|---|---|---|
| Claude Fable 5 / Mythos 5 | always on, only mode | **400** | **not supported** | ✅ | ✅ | ✅ | ✅ |
| Claude Mythos Preview | default on | still accepted | not supported | ✅ | ❌ | ✅ | ❌ |
| Claude Opus 4.8 / Opus 4.7 | opt-in | **400** | ✅ | ✅ | ✅ | ✅ | ✅ |
| Claude Sonnet 5 | on by default | **400** | ✅ | ✅ | ✅ | ✅ | ✅ |
| Claude Opus 4.6 / Sonnet 4.6 | opt-in | accepted but deprecated | ✅ | ✅ | ❌ | ✅ | ❌ |
| Claude Opus 4.5 | not supported | only option | ✅ | ✅ (no xhigh/max) | ❌ | ❌ | ❌ |
| Older / unrecognized models | not supported | only option | ✅ (assumed) | ❌ (unknown) | ❌ | ❌ | ❌ (assumed classic) |

The last row is our own **conservative default** for the capability registry described below, not a documented Anthropic guarantee.

## Decision

### 1. Scope

Ship `DSPy::Reasoning` (shared value object) plus a full Anthropic mapping in this PR. Gemini/OpenRouter/RubyLLM mappings from #247 are tracked as follow-ups. OpenAI is untouched, not even preparatory refactoring.

### 2. `DSPy::Reasoning`: top-level value object, including `.max`

```ruby
module DSPy
  class Reasoning < T::Struct
    class Effort < T::Enum
      enums do
        Low = new('low')
        Medium = new('medium')
        High = new('high')
        XHigh = new('xhigh')
        Max = new('max')
      end
    end

    const :effort, T.nilable(Effort), default: nil
    const :budget_tokens, T.nilable(Integer), default: nil
    const :adaptive, T::Boolean, default: false
    const :disabled, T::Boolean, default: false

    class << self
      def low; new(effort: Effort::Low); end
      def medium; new(effort: Effort::Medium); end
      def high; new(effort: Effort::High); end
      def xhigh; new(effort: Effort::XHigh); end
      def max; new(effort: Effort::Max); end
      def budget(tokens); new(budget_tokens: tokens); end
      def adaptive; new(adaptive: true); end
      def disabled; new(disabled: true); end
    end
  end
end
```

`.max` is **not** in the maintainer's original #247 sketch. It is added intentionally because it's a real, current Anthropic effort level (`output_config.effort: max`), and omitting it would under-serve the "give me maximum capability, cost be damned" use case. This is called out explicitly as an intentional addition, not smuggled in silently.

The namespace is `DSPy::Reasoning` (top-level), matching the maintainer's own #247 comment, despite a minor inconsistency with `DSPy::LM::Message`/`DSPy::LM::Usage` namespacing elsewhere in the codebase.

It is a discriminated union: exactly one reasoning mode is set per instance. A single value can't express "effort X *and* adaptive thinking on" simultaneously — this matches the maintainer's own #247 examples, but is a real expressiveness limit (see Consequences).

### 3. Anthropic effort mapping: real mapping, not a blanket raise

`.low/.medium/.high/.xhigh/.max` map to `output_config: { effort: <value> }`. This does **not** touch `thinking` — per the docs, effort works with or without thinking enabled, and auto-injecting a `thinking` key would be undocumented, invented behavior for models where thinking defaults to off.

`.low/.medium/.high` are validated against `capability.effort` (raises for models that predate the effort parameter entirely, e.g. pre-4.5 models). `.xhigh` and `.max` are additionally validated against `capability.xhigh_effort`/`capability.max_effort` and raise `DSPy::LM::ConfigurationError` for families that don't support them (e.g. `.xhigh` on `claude-opus-4-6`).

### 4. Explicit, named model-capability registry

A small, testable registry drives all model-aware validation, instead of ad-hoc regexes scattered through the adapter (implemented in `lib/dspy/anthropic/lm/model_capabilities.rb`):

```ruby
module DSPy
  module Anthropic
    module LM
      module ModelCapabilities
        Capability = Struct.new(
          :adaptive_thinking,   # :always_on | :default_on | :opt_in | false
          :manual_budget,       # true | :deprecated | false
          :thinking_disable,    # true | false
          :effort,              # true | false — supports output_config.effort at all
          :xhigh_effort,        # true | false
          :max_effort,          # true | false
          :fixed_sampling,      # true => rejects non-default temperature/top_p/top_k
          keyword_init: true
        )

        FAMILIES = [
          [/\Aclaude-(fable|mythos)-5\b/,  FABLE_MYTHOS_5],
          [/\Aclaude-mythos-preview\b/,    MYTHOS_PREVIEW],
          [/\Aclaude-opus-4-[78]\b/,       OPUS_4_7_OR_4_8],
          [/\Aclaude-sonnet-5\b/,          SONNET_5],
          [/\Aclaude-(opus|sonnet)-4-6\b/, OPUS_OR_SONNET_4_6],
          [/\Aclaude-opus-4-5\b/,          OPUS_4_5]
        ].freeze

        DEFAULT = Capability.new(
          adaptive_thinking: false, manual_budget: true, thinking_disable: true,
          effort: false, xhigh_effort: false, max_effort: false, fixed_sampling: false
        )

        def self.for(model)
          _, capability = FAMILIES.find { |pattern, _| pattern.match?(model) }
          capability || DEFAULT
        end
      end
    end
  end
end
```

Patterns are matched with `String#match?` against the bare model name and use `\b` after the version number so dated suffixes (e.g. `claude-sonnet-5-20260315`) still match while unrelated models sharing a numeric prefix (e.g. a hypothetical `claude-sonnet-50`) do not.

`DEFAULT` is deliberately conservative: any model we don't explicitly recognize (older Claude models, or models Anthropic ships after this code is written) keeps working exactly as `dspy-anthropic` behaved before this change (manual `budget_tokens` thinking, unrestricted `temperature`), and only *new* capabilities (`effort`, adaptive-only enforcement, fixed sampling) require the model to be explicitly listed. This means `DSPy::Reasoning.low` on a not-yet-registered future model raises `ConfigurationError` rather than guessing — consistent with "fail loudly," at the cost of registry upkeep (see Consequences).

### 5. Full migration off beta `output_format`/`betas` to `output_config`

Both `lib/dspy/lm/json_strategy.rb` (core `dspy` gem, Anthropic branch only) and `lib/dspy/anthropic/lm/adapters/anthropic_adapter.rb` changed:

- `JSONStrategy#prepare_anthropic_request` no longer builds `request_params[:output_format] = Anthropic::Models::Beta::BetaJSONOutputFormat.new(...)` + `request_params[:betas] = [...]`. It now builds the same JSON schema wrapped in the non-beta `Anthropic::Models::JSONOutputFormat`, with no `betas` key at all.
- `AnthropicAdapter#chat` combines that structured-output format with any effort derived from `reasoning:` into a single `output_config:` hash, and always calls the **non-beta** `@client.messages.create`/`@client.messages.stream` — the beta-client branch (`@client.beta.messages`) was removed entirely, since `output_config`/`thinking` are both supported on the stable API.

```ruby
def build_output_config(output_format)
  config = {}
  config[:format] = output_format if output_format
  config[:effort] = @effort_param if @effort_param
  config.empty? ? nil : config
end
```

This is a net simplification (one client code path instead of two), not just an additive change.

### 6. `temperature`: three-state, model-aware default

`AnthropicAdapter#initialize` uses a sentinel default so it can distinguish "caller didn't mention `temperature`" from "caller explicitly passed `nil`":

```ruby
NOT_SET = Object.new.freeze

def initialize(model:, api_key:, structured_outputs: true, reasoning: nil, temperature: NOT_SET, max_tokens: 4096)
  ...
  @temperature_explicit = !temperature.equal?(NOT_SET)
  @temperature = @temperature_explicit ? temperature : nil
  @capability = ModelCapabilities.for(model)
  @thinking_param = build_thinking_param(reasoning) # nil, or a Hash with a :type key
  ...
end

private

def effective_temperature
  return @temperature if @temperature_explicit # nil => caller wants it omitted; float => send as-is
  return nil if @capability.fixed_sampling
  return nil if thinking_active? # thinking_active? is false when @thinking_param is nil or {type: :disabled}

  0.0 # legacy default, unchanged for classic models with no active thinking
end
```

Effective `temperature` sent on each request:

| Caller passed | Behavior |
|---|---|
| nothing (`NOT_SET`) | omit the key if `capability.fixed_sampling` **or** this request sends an active `thinking` key (i.e. `reasoning:` is `.budget(n)` or `.adaptive`); otherwise legacy default `0.0` |
| `temperature: nil` | always omitted, regardless of model or `reasoning:` |
| `temperature: <float>` | always sent as given, regardless of model or `reasoning:` (fails loudly via the API's own 400 if incompatible — we don't second-guess an explicit value) |

Two independent reasons feed the implicit omission:
1. **Model-level**: `claude-sonnet-5`/`claude-opus-4-7`/`claude-opus-4-8`/`claude-fable-5`/`claude-mythos-5` reject non-default `temperature` on *every* request, thinking or not (`capability.fixed_sampling`). This directly fixes #256's default-path case.
2. **Feature-level, model-independent**: Anthropic's extended-thinking docs state that *"Thinking isn't compatible with `temperature` or `top_k` modifications."* So whenever `reasoning:` produces an active `thinking` key (`.budget(n)`, `.adaptive`), the implicit `temperature: 0.0` default is omitted even on classic models like `claude-opus-4-6` where `fixed_sampling` is `false`. `.disabled` does **not** trigger this (thinking is explicitly off, so classic temperature behavior applies). `.low/.medium/.high/.xhigh/.max` (effort-only, no `thinking` key) also do **not** trigger this — they leave the model's own `temperature` behavior untouched unless the model is separately `fixed_sampling`.

This satisfies requirement #5 from the maintainer: the *default* call path (no `reasoning:`, no `temperature:`) now omits the parameter automatically for the fixed-sampling models, fixing the reported bug even for users who never touch the new `reasoning:` API — and it also fixes the same class of bug for anyone who *does* use `.budget(n)`/`.adaptive` on an older model.

### 7. `max_tokens`: general constructor kwarg

`max_tokens: 4096` keyword, same default as before, no breaking change. Needed both generally (previously unconditionally hard-coded) and for `budget_tokens` validation to be meaningful.

### 8. Validation, eager at construction time

- `budget_tokens < max_tokens` (existing Anthropic requirement).
- `budget_tokens >= 1024` (Anthropic's documented minimum).
- `.budget(n)` raises `ConfigurationError` if `capability.manual_budget == false` (e.g. Sonnet 5, Opus 4.7/4.8, Fable 5, Mythos 5).
- `.adaptive` raises if `capability.adaptive_thinking == false` (old models).
- `.disabled` raises if `capability.thinking_disable == false` (Fable 5, Mythos 5, Mythos Preview).
- `.xhigh`/`.max` raise if the corresponding capability flag is false.
- `.low/.medium/.high` raise if `capability.effort == false` (unrecognized/old models via `DEFAULT`).

All validated in the constructor (`DSPy::LM.new(...)` time), not on first request — cheap failure, matches "fail loudly."

## Alternatives Considered

### A. Raw `extra_params:` hash
**Rejected** by the maintainer in #247 before this work started.

### B. Hard-code just the two models named in the issue (`sonnet-5`, `opus-4-8`)
**Rejected**: the doc research surfaced seven distinct family behaviors, not two, making a real registry both necessary and well-informed rather than speculative.

### C. Auto-detect via API-error catch + retry
**Rejected for now**: hides the problem, adds latency, doesn't compose with `reasoning:`. Still a candidate defensive fallback for models missing from the registry (see Follow-ups).

### D. Keep the beta `output_format`/`betas` path and add `output_config` alongside it
**Rejected**: running two structured-output code paths (beta vs. non-beta) would be more code, not less, and the maintainer specifically asked that reasoning and structured outputs compose under one request shape rather than compete.

### E. Full 5-provider implementation of #247 in one PR
**Rejected for PR sizing reasons** — see Decision §1.

## Implementation

### Files touched

- `lib/dspy/lm/reasoning.rb` (new, core gem) — `DSPy::Reasoning` struct + factories including `.max`.
- `lib/dspy/lm.rb` — `require_relative 'lm/reasoning'`.
- `lib/dspy/lm/json_strategy.rb` — Anthropic branch: build non-beta `Anthropic::Models::JSONOutputFormat` instead of the beta type; no `betas` key.
- `lib/dspy/anthropic/lm/adapters/anthropic_adapter.rb` — `reasoning:`, `temperature:` (sentinel), `max_tokens:` kwargs; `ModelCapabilities` lookup; `output_config` request building; beta-client branch removed; validation at construction time.
- `lib/dspy/anthropic/lm/model_capabilities.rb` (new) — the registry from §4.
- `spec/unit/dspy/lm/reasoning_spec.rb` (new).
- `spec/unit/dspy/anthropic/lm/model_capabilities_spec.rb` (new) — table-driven: one example per named family + the `DEFAULT` fallback, including a dated-suffix match case per family.
- `spec/integration/dspy/lm/adapters/anthropic_adapter_spec.rb` (extended significantly).
- `spec/integration/dspy/lm/json_strategy_spec.rb` (updated for the non-beta shape).
- `docs/src/advanced/reasoning.md` (new) — documents `reasoning:`/`temperature:`/`max_tokens:` for Anthropic; explicit "other providers not yet supported" note.
- `docs/src/production/troubleshooting.md` — entry for the exact #256 error message.
- `CHANGELOG.md` — Unreleased entry.

### Anthropic `DSPy::Reasoning` → request mapping

| `DSPy::Reasoning` | Request shape | Model-capability gate |
|---|---|---|
| `nil` (not passed) | *(no `thinking`/`output_config.effort`)* | — |
| `.low/.medium/.high` | `output_config: { effort: <value> }` | `capability.effort` |
| `.xhigh` | `output_config: { effort: 'xhigh' }` | `capability.xhigh_effort` |
| `.max` | `output_config: { effort: 'max' }` | `capability.max_effort` |
| `.budget(n)` | `thinking: { type: 'enabled', budget_tokens: n }` | `capability.manual_budget` truthy; `1024 <= n < max_tokens` |
| `.adaptive` | `thinking: { type: 'adaptive' }` | `capability.adaptive_thinking` truthy |
| `.disabled` | `thinking: { type: 'disabled' }` | `capability.thinking_disable` |

## Consequences

### Positive
- Actually fixes #256, including the default call path (no `reasoning:` needed) — the case most users hit first.
- Effort levels are a real, useful feature now, not a documented dead-end.
- Structured outputs + reasoning share one request shape, and the beta-only code path is removed — net reduction in adapter complexity.
- Registry-based validation gives specific, actionable errors instead of raw 400s bubbling up as generic `AdapterError`.
- No breaking changes to existing callers who pass neither `reasoning:` nor `temperature:` nor `max_tokens:` on already-classic models.

### Negative / Risks
- **Registry maintenance burden**: Anthropic ships new model-family generations every few months. A model not yet added gets the conservative `DEFAULT` (classic behavior, no new capabilities), which is safe but means `DSPy::Reasoning.low` etc. won't work on brand-new models until the registry is updated. Mitigated by keeping the registry a single array literal that's easy to extend.
- A single `DSPy::Reasoning` value can't express "effort X *and* adaptive thinking on" simultaneously in one call.
- `#247` remains open after this PR (Gemini/OpenRouter/RubyLLM untouched, OpenAI explicitly deferred).
- Thinking-content response blocks (`content_block.type == "thinking"`) are still silently dropped by `AnthropicAdapter#chat`'s response parsing. Out of scope for #256, tracked as a follow-up.

### Follow-ups (tracked separately, not part of this PR)
- Gemini 2.5 (`thinkingBudget`) vs. Gemini 3 (`thinkingLevel`) mapping.
- OpenRouter `request_options.extra_body.reasoning`.
- RubyLLM `chat.with_thinking(effort:/budget:)` — only if kept thin; RubyLLM's exact kwarg names need verification first.
- OpenAI `reasoning_effort` (Responses API migration question first) — explicitly deferred, not started.
- Surface Anthropic `thinking` response blocks via `DSPy::LM::Response#metadata`.
- Defensive fallback: catch a 400 mentioning "temperature is deprecated"/"budget_tokens" for models missing from the registry and raise a clearer `DSPy::LM::AdapterError` pointing at the registry gap.
- A VCR-recorded integration test against a real adaptive-thinking-capable model, to confirm response parsing doesn't choke on `thinking` content blocks.

## References
- [Issue #256](https://github.com/vicentereig/dspy.rb/issues/256)
- [Issue #247](https://github.com/vicentereig/dspy.rb/issues/247)
- `lib/dspy/anthropic/lm/adapters/anthropic_adapter.rb`
- `lib/dspy/lm/json_strategy.rb`
- `lib/dspy/lm/adapter_factory.rb`
- `anthropic` gem `>= 1.28.0`: `Anthropic::Models::OutputConfig`, `Anthropic::Models::ThinkingConfigParam` (incl. `ThinkingConfigAdaptive`), `Anthropic::Models::MessageCreateParams`
- Anthropic docs: [Adaptive thinking](https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking), [Effort](https://platform.claude.com/docs/en/build-with-claude/effort)
