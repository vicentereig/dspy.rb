# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::AdapterFactory do
  describe '.create' do
    it 'creates OpenAI adapter for openai/ prefixed model' do
      adapter = described_class.create('openai/gpt-4', api_key: 'test-key')
      
      expect(adapter).to be_a(DSPy::LM::OpenAIAdapter)
      expect(adapter.model).to eq('gpt-4')
    end

    it 'creates Anthropic adapter for anthropic/ prefixed model' do
      adapter = described_class.create('anthropic/claude-3-sonnet', api_key: 'test-key')
      
      expect(adapter).to be_a(DSPy::LM::AnthropicAdapter)
      expect(adapter.model).to eq('claude-3-sonnet')
    end

    it 'raises error for legacy model format without provider' do
      expect {
        described_class.create('gpt-3.5-turbo', api_key: 'test-key')
      }.to raise_error(ArgumentError, /model_id must include provider/)
    end

    it 'raises error for unsupported provider' do
      expect {
        described_class.create('unsupported/model', api_key: 'test-key')
      }.to raise_error(DSPy::LM::UnsupportedProviderError, /Unsupported provider: unsupported/)
    end

    it 'passes model and api_key to adapter' do
      expect(DSPy::LM::OpenAIAdapter).to receive(:new)
        .with(model: 'gpt-4', api_key: 'test-key')
        .and_call_original
      
      described_class.create('openai/gpt-4', api_key: 'test-key')
    end
  end
end
