# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::MessageBuilder do
  let(:builder) { described_class.new }

  describe '#initialize' do
    it 'starts with empty messages' do
      expect(builder.messages).to eq([])
    end
  end

  describe '#system' do
    it 'adds a system message' do
      builder.system('You are a helpful assistant')
      
      expect(builder.messages).to eq([
        { role: 'system', content: 'You are a helpful assistant' }
      ])
    end

    it 'returns self for chaining' do
      expect(builder.system('test')).to eq(builder)
    end
  end

  describe '#user' do
    it 'adds a user message' do
      builder.user('What is AI?')
      
      expect(builder.messages).to eq([
        { role: 'user', content: 'What is AI?' }
      ])
    end

    it 'returns self for chaining' do
      expect(builder.user('test')).to eq(builder)
    end
  end

  describe '#assistant' do
    it 'adds an assistant message' do
      builder.assistant('AI stands for Artificial Intelligence...')
      
      expect(builder.messages).to eq([
        { role: 'assistant', content: 'AI stands for Artificial Intelligence...' }
      ])
    end

    it 'returns self for chaining' do
      expect(builder.assistant('test')).to eq(builder)
    end
  end

  describe 'message ordering' do
    it 'preserves the order of messages' do
      builder
        .system('You are a teacher')
        .user('What is 2+2?')
        .assistant('2+2 equals 4')
        .user('Why?')
      
      expect(builder.messages).to eq([
        { role: 'system', content: 'You are a teacher' },
        { role: 'user', content: 'What is 2+2?' },
        { role: 'assistant', content: '2+2 equals 4' },
        { role: 'user', content: 'Why?' }
      ])
    end
  end

  describe 'edge cases' do
    it 'handles empty content' do
      builder.user('')
      expect(builder.messages).to eq([{ role: 'user', content: '' }])
    end

    it 'handles nil content by converting to empty string' do
      builder.user(nil)
      expect(builder.messages).to eq([{ role: 'user', content: '' }])
    end

    it 'handles multiline content' do
      multiline = <<~TEXT
        Line 1
        Line 2
        Line 3
      TEXT
      
      builder.user(multiline.strip)
      expect(builder.messages.first[:content]).to eq("Line 1\nLine 2\nLine 3")
    end
  end
end