# frozen_string_literal: true

module DSPy
  module Anthropic
    module LM
      # Per-model-family reasoning/sampling capabilities.
      #
      # Anthropic ships new Claude model generations every few months, each with
      # different `thinking`/`effort`/sampling-parameter support. Rather than
      # scatter model-name regexes through the adapter, this registry centralizes
      # them so validation logic can ask a single question ("does this model
      # support X?") instead of re-deriving it from the model string each time.
      #
      # Source (verified 2026-07-09):
      # - https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking
      # - https://platform.claude.com/docs/en/build-with-claude/effort
      #
      # Unrecognized models (including future Anthropic releases not yet added
      # here) fall back to +DEFAULT+: the classic, pre-adaptive-thinking
      # behavior this gem has always assumed (manual `budget_tokens` only, no
      # named effort tiers, unrestricted `temperature`). This is a deliberately
      # conservative choice: it keeps existing behavior for models we don't
      # know about, at the cost of `DSPy::Reasoning` effort tiers not working
      # on brand-new models until this registry is updated.
      module ModelCapabilities
        Capability = Struct.new(
          :adaptive_thinking,  # :always_on | :default_on | :opt_in | false
          :manual_budget,      # true | :deprecated | false
          :thinking_disable,   # true | false — supports `thinking: {type: 'disabled'}`
          :effort,             # true | false — supports `output_config.effort` at all
          :xhigh_effort,       # true | false
          :max_effort,         # true | false
          :fixed_sampling,     # true => rejects non-default temperature/top_p/top_k
          keyword_init: true
        ) do
          def to_h
            {
              adaptive_thinking: adaptive_thinking,
              manual_budget: manual_budget,
              thinking_disable: thinking_disable,
              effort: effort,
              xhigh_effort: xhigh_effort,
              max_effort: max_effort,
              fixed_sampling: fixed_sampling
            }
          end
        end
        private_constant :Capability

        FABLE_MYTHOS_5 = Capability.new(
          adaptive_thinking: :always_on, manual_budget: false, thinking_disable: false,
          effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
        ).freeze

        MYTHOS_PREVIEW = Capability.new(
          adaptive_thinking: :default_on, manual_budget: true, thinking_disable: false,
          effort: true, xhigh_effort: false, max_effort: true, fixed_sampling: false
        ).freeze

        OPUS_4_7_OR_4_8 = Capability.new(
          adaptive_thinking: :opt_in, manual_budget: false, thinking_disable: true,
          effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
        ).freeze

        SONNET_5 = Capability.new(
          adaptive_thinking: :default_on, manual_budget: false, thinking_disable: true,
          effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
        ).freeze

        OPUS_OR_SONNET_4_6 = Capability.new(
          adaptive_thinking: :opt_in, manual_budget: :deprecated, thinking_disable: true,
          effort: true, xhigh_effort: false, max_effort: true, fixed_sampling: false
        ).freeze

        OPUS_4_5 = Capability.new(
          adaptive_thinking: false, manual_budget: true, thinking_disable: true,
          effort: true, xhigh_effort: false, max_effort: false, fixed_sampling: false
        ).freeze

        # Conservative fallback for any model not explicitly listed above,
        # including older Claude models and models Anthropic ships after this
        # file is written. Matches this gem's pre-#256 behavior exactly.
        DEFAULT = Capability.new(
          adaptive_thinking: false, manual_budget: true, thinking_disable: true,
          effort: false, xhigh_effort: false, max_effort: false, fixed_sampling: false
        ).freeze

        # Ordered [pattern, capability] pairs. Patterns are matched with
        # `String#match?` against the bare model name (i.e. without the
        # "anthropic/" provider prefix DSPy::LM strips before constructing the
        # adapter). `\b` after the version number allows dated suffixes
        # (e.g. "claude-sonnet-5-20260315") while still rejecting unrelated
        # models that merely share a numeric prefix (e.g. "claude-sonnet-50").
        FAMILIES = [
          [/\Aclaude-(fable|mythos)-5\b/, FABLE_MYTHOS_5],
          [/\Aclaude-mythos-preview\b/, MYTHOS_PREVIEW],
          [/\Aclaude-opus-4-[78]\b/, OPUS_4_7_OR_4_8],
          [/\Aclaude-sonnet-5\b/, SONNET_5],
          [/\Aclaude-(opus|sonnet)-4-6\b/, OPUS_OR_SONNET_4_6],
          [/\Aclaude-opus-4-5\b/, OPUS_4_5]
        ].freeze

        def self.for(model)
          _, capability = FAMILIES.find { |pattern, _| pattern.match?(model) }
          capability || DEFAULT
        end
      end
    end
  end
end
