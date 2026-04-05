# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Support::OpenAISDKWarning do
  around do |example|
    original_warned = described_class.instance_variable_get(:@warned)
    described_class.instance_variable_set(:@warned, nil)
    example.run
  ensure
    described_class.instance_variable_set(:@warned, original_warned)
  end

  it 'detects the community ruby-openai constant shape' do
    stub_const('OpenAI', Module.new)
    stub_const('OpenAI::Client', Class.new)

    expect(described_class.community_gem_loaded?).to be(true)
  end

  it 'does not warn for the official openai gem constant shape' do
    stub_const('OpenAI', Module.new)
    stub_const('OpenAI::Client', Class.new)
    stub_const('OpenAI::Internal', Module.new)

    expect(described_class.community_gem_loaded?).to be(false)
  end

  it 'warns at most once when the community gem is loaded' do
    stub_const('OpenAI', Module.new)
    stub_const('OpenAI::Client', Class.new)

    expect(Kernel).to receive(:warn).with(described_class::WARNING_MESSAGE).once

    described_class.warn_if_community_gem_loaded!
    described_class.warn_if_community_gem_loaded!
  end
end
