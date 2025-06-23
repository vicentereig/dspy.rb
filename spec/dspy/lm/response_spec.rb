# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::Response do
  describe '#initialize' do
    it 'creates response with content, usage, and metadata' do
      response = described_class.new(
        content: 'Hello world',
        usage: { 'total_tokens' => 10 },
        metadata: { provider: 'openai', model: 'gpt-4' }
      )
      
      expect(response.content).to eq('Hello world')
      expect(response.usage).to eq({ 'total_tokens' => 10 })
      expect(response.metadata).to eq({ provider: 'openai', model: 'gpt-4' })
    end

    it 'handles nil values gracefully' do
      response = described_class.new(
        content: nil,
        usage: nil,
        metadata: nil
      )
      
      expect(response.content).to be_nil
      expect(response.usage).to be_nil
      expect(response.metadata).to be_nil
    end
  end

  describe '#to_h' do
    it 'converts response to hash format' do
      response = described_class.new(
        content: 'Hello world',
        usage: { 'total_tokens' => 10 },
        metadata: { provider: 'openai' }
      )
      
      hash = response.to_h
      expect(hash).to eq({
        content: 'Hello world',
        usage: { 'total_tokens' => 10 },
        metadata: { provider: 'openai' }
      })
    end
  end

  describe 'attribute accessors' do
    let(:response) do
      described_class.new(
        content: 'Test content',
        usage: { 'total_tokens' => 15 },
        metadata: { provider: 'anthropic', model: 'claude-3' }
      )
    end

    it 'provides read access to content' do
      expect(response.content).to eq('Test content')
    end

    it 'provides read access to usage' do
      expect(response.usage).to eq({ 'total_tokens' => 15 })
    end

    it 'provides read access to metadata' do
      expect(response.metadata).to eq({ provider: 'anthropic', model: 'claude-3' })
    end
  end
end
