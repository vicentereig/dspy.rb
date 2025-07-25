# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::OpenAIAdapter do
  let(:model) { 'gpt-4' }
  let(:api_key) { 'test-api-key' }
  let(:mock_client) { double('OpenAI::Client') }
  let(:mock_chat) { double('OpenAI::Chat') }
  let(:mock_completions) { double('OpenAI::Completions') }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:completions).and_return(mock_completions)
  end

  describe '#initialize' do
    it 'creates OpenAI client with api_key' do
      expect(OpenAI::Client).to receive(:new).with(api_key: api_key)
      
      described_class.new(model: model, api_key: api_key)
    end

    it 'stores model' do
      adapter = described_class.new(model: model, api_key: api_key)
      expect(adapter.model).to eq(model)
    end
  end

  describe '#chat' do
    let(:messages) do
      [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]
    end
    
    let(:mock_response) do
      double('OpenAI::Response',
             id: 'resp-123',
             created: 1234567890,
             choices: [
               double('Choice', 
                      message: double('Message', content: 'Hello back!'))
             ],
             usage: double('Usage', 
                          total_tokens: 25,
                          to_h: { 'total_tokens' => 25 }))
    end

    it 'makes successful API call and returns normalized response' do
      expect(mock_completions).to receive(:create).with(
        model: model,
        messages: messages,
        temperature: 0.0
      ).and_return(mock_response)

      result = described_class.new(model: model, api_key: api_key).chat(messages: messages)

      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Hello back!')
      expect(result.usage).to be_a(DSPy::LM::OpenAIUsage)
      expect(result.usage.total_tokens).to eq(25)
      expect(result.metadata[:provider]).to eq('openai')
      expect(result.metadata[:model]).to eq(model)
      expect(result.metadata[:response_id]).to eq('resp-123')
      expect(result.metadata[:created]).to eq(1234567890)
    end

    it 'handles streaming with block' do
      block_called = false
      test_block = proc { |chunk| block_called = true }

      expect(mock_completions).to receive(:create).with(
        hash_including(stream: anything)
      ).and_return(mock_response)

      described_class.new(model: model, api_key: api_key).chat(messages: messages, &test_block)
    end

    it 'handles API errors gracefully' do
      allow(mock_completions).to receive(:create)
        .and_raise(StandardError, 'API Error')

      expect {
        described_class.new(model: model, api_key: api_key).chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /OpenAI adapter error: API Error/)
    end
  end

  describe '#normalize_messages' do
    let(:messages) do
      [
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' }
      ]
    end

    it 'returns messages as-is for OpenAI format' do
      adapter = described_class.new(model: model, api_key: api_key)
      normalized = adapter.send(:normalize_messages, messages)
      expect(normalized).to eq(messages)
    end
  end
end
