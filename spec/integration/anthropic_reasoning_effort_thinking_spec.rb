# frozen_string_literal: true

require 'spec_helper'

# PR #257 review (vicentereig, 2026-07-09): proves against the real Anthropic
# API that an "opt-in adaptive" model (Opus 4.7/4.8, Opus/Sonnet 4.6) accepts
# `thinking: { type: "adaptive" }` combined with `output_config.effort` in a
# single request — the request shape the AnthropicAdapter now builds for any
# DSPy::Reasoning effort tier on those model families (see
# lib/dspy/anthropic/lm/adapters/anthropic_adapter.rb#build_thinking_param and
# adr/019-anthropic-reasoning-temperature-config.md §3).
#
# Recorded once against the live API with a real ANTHROPIC_API_KEY (VCR
# scrubs the key from the cassette before it's written — see
# spec/spec_helper.rb's `filter_sensitive_data('<ANTHROPIC_API_KEY>')`).
# Once spec/vcr_cassettes/anthropic/reasoning_effort_adaptive_opus_4_8.yml
# exists, this spec replays it and needs no API key at all.
RSpec.describe 'Anthropic reasoning: effort tiers on opt-in adaptive models', :vcr do
  before do
    skip "ANTHROPIC_API_KEY not set (only required to (re-)record the cassette)" unless ENV['ANTHROPIC_API_KEY']
  end

  it 'accepts thinking: adaptive together with output_config.effort on claude-opus-4-8',
     vcr: { cassette_name: 'anthropic/reasoning_effort_adaptive_opus_4_8' } do
    adapter = DSPy::Anthropic::LM::Adapters::AnthropicAdapter.new(
      model: 'claude-opus-4-8',
      api_key: ENV['ANTHROPIC_API_KEY'],
      reasoning: DSPy::Reasoning.high
    )

    response = adapter.chat(messages: [
      { role: 'user', content: 'What is 2 + 2? Reply with only the digit, no explanation.' }
    ])

    expect(response).to be_a(DSPy::LM::Response)
    expect(response.content).to include('4')
  end
end
