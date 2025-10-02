# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/dspy/lm/chat_strategy'

RSpec.describe DSPy::LM::ChatStrategy do
  let(:adapter) { instance_double(DSPy::LM::Adapter) }
  let(:strategy) { described_class.new(adapter) }

  describe '#prepare_request' do
    it 'does not modify messages' do
      messages = [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]
      request_params = {}

      original_messages = messages.dup
      strategy.prepare_request(messages, request_params)

      expect(messages).to eq(original_messages)
    end

    it 'does not add request parameters' do
      messages = [{ role: 'user', content: 'Hello' }]
      request_params = {}

      strategy.prepare_request(messages, request_params)

      expect(request_params).to be_empty
    end
  end

  describe '#extract_json' do
    let(:response) { DSPy::LM::Response.new(content: 'Plain text response', usage: nil, metadata: {}) }

    it 'returns nil (no JSON extraction for chat)' do
      expect(strategy.extract_json(response)).to be_nil
    end
  end

  describe '#name' do
    it 'returns strategy name' do
      expect(strategy.name).to eq('chat')
    end
  end

  describe 'integration with LM' do
    it 'passes through messages unchanged to adapter' do
      messages = [
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' }
      ]
      request_params = {}

      # Prepare request
      strategy.prepare_request(messages, request_params)

      # Verify no changes
      expect(messages).to eq([
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' }
      ])
      expect(request_params).to eq({})
    end

    it 'does not extract JSON from responses' do
      response_with_json = DSPy::LM::Response.new(
        content: '{"name": "John", "age": 30}',
        usage: nil,
        metadata: {}
      )

      # Should return nil, not extract JSON
      expect(strategy.extract_json(response_with_json)).to be_nil
    end
  end
end
