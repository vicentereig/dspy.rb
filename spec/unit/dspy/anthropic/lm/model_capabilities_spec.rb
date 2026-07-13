# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Anthropic::LM::ModelCapabilities do
  describe '.for' do
    # Source: https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking
    #         https://platform.claude.com/docs/en/build-with-claude/effort
    # Verified 2026-07-09.
    {
      'claude-fable-5' => {
        adaptive_thinking: :always_on, manual_budget: false, thinking_disable: false,
        effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
      },
      'claude-mythos-5' => {
        adaptive_thinking: :always_on, manual_budget: false, thinking_disable: false,
        effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
      },
      # fixed_sampling: true per PR #257 review (vicentereig, 2026-07-11) — Anthropic
      # documents Mythos Preview as rejecting non-default temperature/top_p/top_k,
      # same as Fable 5/Mythos 5/Sonnet 5/Opus 4.7/4.8.
      'claude-mythos-preview' => {
        adaptive_thinking: :default_on, manual_budget: true, thinking_disable: false,
        effort: true, xhigh_effort: false, max_effort: true, fixed_sampling: true
      },
      'claude-opus-4-8' => {
        adaptive_thinking: :opt_in, manual_budget: false, thinking_disable: true,
        effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
      },
      'claude-opus-4-7' => {
        adaptive_thinking: :opt_in, manual_budget: false, thinking_disable: true,
        effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
      },
      'claude-sonnet-5' => {
        adaptive_thinking: :default_on, manual_budget: false, thinking_disable: true,
        effort: true, xhigh_effort: true, max_effort: true, fixed_sampling: true
      },
      'claude-opus-4-6' => {
        adaptive_thinking: :opt_in, manual_budget: :deprecated, thinking_disable: true,
        effort: true, xhigh_effort: false, max_effort: true, fixed_sampling: false
      },
      'claude-sonnet-4-6' => {
        adaptive_thinking: :opt_in, manual_budget: :deprecated, thinking_disable: true,
        effort: true, xhigh_effort: false, max_effort: true, fixed_sampling: false
      },
      'claude-opus-4-5' => {
        adaptive_thinking: false, manual_budget: true, thinking_disable: true,
        effort: true, xhigh_effort: false, max_effort: false, fixed_sampling: false
      }
    }.each do |model, expected|
      it "returns the documented capabilities for #{model}" do
        capability = described_class.for(model)

        expect(capability.to_h).to eq(expected)
      end

      it "matches #{model} with a dated suffix (e.g. #{model}-20260315)" do
        capability = described_class.for("#{model}-20260315")

        expect(capability.to_h).to eq(expected)
      end
    end

    it 'falls back to the conservative DEFAULT for an unrecognized model' do
      capability = described_class.for('claude-3-5-sonnet-20241022')

      expect(capability).to eq(described_class::DEFAULT)
      expect(capability.to_h).to eq(
        adaptive_thinking: false, manual_budget: true, thinking_disable: true,
        effort: false, xhigh_effort: false, max_effort: false, fixed_sampling: false
      )
    end

    it 'does not fuzzy-match a similar but distinct model name (claude-sonnet-50 vs claude-sonnet-5)' do
      capability = described_class.for('claude-sonnet-50-hypothetical')

      expect(capability).to eq(described_class::DEFAULT)
    end
  end
end
