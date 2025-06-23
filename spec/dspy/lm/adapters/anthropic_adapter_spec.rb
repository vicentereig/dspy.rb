# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::AnthropicAdapter do
  let(:adapter) { described_class.new(model: 'claude-3-sonnet', api_key: 'test-key') }
  let(:mock_client) { instance_double(Anthropic::Client) }
  let(:mock_messages) { double('Anthropic::Messages') }

  before do
    allow(Anthropic::Client).to receive(:new).with(api_key: 'test-key').and_return(mock_client)
    allow(mock_client).to receive(:messages).and_return(mock_messages)
  end

  describe '#initialize' do
    it 'creates Anthropic client with api_key' do
      expect(Anthropic::Client).to receive(:new).with(api_key: 'test-key')
      
      described_class.new(model: 'claude-3-sonnet', api_key: 'test-key')
    end

    it 'stores model' do
      adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key')
      expect(adapter.model).to eq('claude-3-sonnet')
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
      double('Anthropic::Response',
             id: 'msg-123',
             role: 'assistant',
             content: [double('Content', text: 'Hello back!')],
             usage: double('Usage', 
                          total_tokens: 30,
                          to_h: { 'total_tokens' => 30 }))
    end

    it 'makes successful API call and returns normalized response' do
      expect(mock_messages).to receive(:create).with(
        parameters: {
          model: 'claude-3-sonnet',
          messages: [{ role: 'user', content: 'Hello' }],
          system: 'You are helpful',
          max_tokens: 4096,
          temperature: 0.0
        }
      ).and_return(mock_response)

      result = adapter.chat(messages: messages)

      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Hello back!')
      expect(result.usage).to eq({ 'total_tokens' => 30 })
      expect(result.metadata[:provider]).to eq('anthropic')
      expect(result.metadata[:model]).to eq('claude-3-sonnet')
      expect(result.metadata[:response_id]).to eq('msg-123')
      expect(result.metadata[:role]).to eq('assistant')
    end

    it 'handles streaming with block' do
      block_called = false
      test_block = proc { |chunk| block_called = true }

      allow(mock_messages).to receive(:stream).and_yield(
        double('Chunk', 
               delta: double('Delta', text: 'Hello'),
               respond_to?: ->(method) { method == :delta })
      )

      result = adapter.chat(messages: messages, &test_block)
      
      expect(result.metadata[:streaming]).to be_truthy
    end

    it 'handles API errors gracefully' do
      allow(mock_messages).to receive(:create)
        .and_raise(StandardError, 'API Error')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Anthropic adapter error: API Error/)
    end
  end

  describe '#extract_system_message' do
    it 'separates system message from user messages' do
      messages = [
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' },
        { role: 'assistant', content: 'Assistant reply' }
      ]

      system_msg, user_msgs = adapter.send(:extract_system_message, messages)

      expect(system_msg).to eq('System prompt')
      expect(user_msgs).to eq([
        { role: 'user', content: 'User message' },
        { role: 'assistant', content: 'Assistant reply' }
      ])
    end

    it 'handles messages without system prompt' do
      messages = [
        { role: 'user', content: 'User message' }
      ]

      system_msg, user_msgs = adapter.send(:extract_system_message, messages)

      expect(system_msg).to be_nil
      expect(user_msgs).to eq(messages)
    end
  end
end
