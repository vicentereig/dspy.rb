# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  # Shared, provider-agnostic reasoning/thinking configuration.
  #
  # Passed to +DSPy::LM.new(..., reasoning: ...)+. Each adapter is responsible
  # for mapping the resulting struct onto its own provider's request shape and
  # raising +DSPy::LM::ConfigurationError+ for combinations it can't support
  # (see the Anthropic adapter's +ModelCapabilities+ registry).
  #
  # Exactly one reasoning mode is set per instance (effort tier, manual token
  # budget, adaptive thinking, or explicitly disabled) — this is a
  # discriminated union, not a combinable set of options.
  class Reasoning < T::Struct
    extend T::Sig

    # Named effort tiers, as documented by Anthropic's `output_config.effort`
    # (https://platform.claude.com/docs/en/build-with-claude/effort).
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

    sig { params(args: T.untyped).void }
    def initialize(**args)
      super

      active = {
        effort: !effort.nil?,
        budget_tokens: !budget_tokens.nil?,
        adaptive: adaptive,
        disabled: disabled
      }.select { |_, set| set }.keys

      if active.size > 1
        raise DSPy::LM::ConfigurationError,
          "DSPy::Reasoning represents exactly one reasoning mode at a time " \
          "(effort, budget_tokens, adaptive, or disabled), but #{active.size} were set: #{active.join(', ')}."
      end
    end

    class << self
      extend T::Sig

      sig { returns(Reasoning) }
      def low
        new(effort: Effort::Low)
      end

      sig { returns(Reasoning) }
      def medium
        new(effort: Effort::Medium)
      end

      sig { returns(Reasoning) }
      def high
        new(effort: Effort::High)
      end

      sig { returns(Reasoning) }
      def xhigh
        new(effort: Effort::XHigh)
      end

      sig { returns(Reasoning) }
      def max
        new(effort: Effort::Max)
      end

      sig { params(tokens: Integer).returns(Reasoning) }
      def budget(tokens)
        new(budget_tokens: tokens)
      end

      sig { returns(Reasoning) }
      def adaptive
        new(adaptive: true)
      end

      sig { returns(Reasoning) }
      def disabled
        new(disabled: true)
      end
    end
  end
end
