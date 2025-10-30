# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::AdapterFactory do
  describe '.create' do
    it 'creates OpenAI adapter for openai/ prefixed model' do
      adapter = described_class.create('openai/gpt-4', api_key: 'test-key')
      
      expect(adapter).to be_a(DSPy::OpenAI::LM::Adapters::OpenAIAdapter)
      expect(adapter.model).to eq('gpt-4')
    end

    it 'creates OpenAI adapter for OpenRouter models' do
      adapter = described_class.create('openrouter/x-ai/grok-4-fast:free', api_key: 'test-key')

      expect(adapter).to be_a(DSPy::OpenAI::LM::Adapters::OpenAIAdapter)
      expect(adapter.model).to eq('x-ai/grok-4-fast:free')
    end

    it 'strips the openrouter/ prefix for OpenRouter models' do
      adapter = described_class.create('openrouter/x-ai/grok-4-fast:free', api_key: 'test-key')
      expect(adapter.model).to eq('x-ai/grok-4-fast:free')
    end

    it 'creates Anthropic adapter for anthropic/ prefixed model' do
      adapter = described_class.create('anthropic/claude-3-sonnet', api_key: 'test-key')
      
      expect(adapter).to be_a(DSPy::Anthropic::LM::Adapters::AnthropicAdapter)
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
      expect(DSPy::OpenAI::LM::Adapters::OpenAIAdapter).to receive(:new)
        .with(model: 'gpt-4', api_key: 'test-key')
        .and_call_original
      
      described_class.create('openai/gpt-4', api_key: 'test-key')
    end

    it 'passes Openrouter-specific options to the adapter' do
      adapter = described_class.create(
        'openrouter/x-ai/grok-4-fast:free',
        api_key: 'test-key',
        http_referrer: 'https://example.com',
        x_title: 'MyApp'
      )

      expect(adapter).to be_a(DSPy::LM::OpenrouterAdapter)
      expect(adapter.model).to eq('x-ai/grok-4-fast:free')

      request_params = adapter.send(:default_request_params)
      expect(request_params).to have_key(:request_options)
      expect(request_params[:request_options]).to have_key(:extra_headers)
      expect(request_params[:request_options][:extra_headers]).to include(
        'X-Title' => 'MyApp',
        'HTTP-Referer' => 'https://example.com'
      )
    end
  end
end
