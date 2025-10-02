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
      
      expect(builder.messages.size).to eq(1)
      message = builder.messages.first
      expect(message).to be_a(DSPy::LM::Message)
      expect(message.role).to eq(DSPy::LM::Message::Role::System)
      expect(message.content).to eq('You are a helpful assistant')
    end

    it 'returns self for chaining' do
      expect(builder.system('test')).to eq(builder)
    end
  end

  describe '#user' do
    it 'adds a user message' do
      builder.user('What is AI?')
      
      expect(builder.messages.size).to eq(1)
      message = builder.messages.first
      expect(message).to be_a(DSPy::LM::Message)
      expect(message.role).to eq(DSPy::LM::Message::Role::User)
      expect(message.content).to eq('What is AI?')
    end

    it 'returns self for chaining' do
      expect(builder.user('test')).to eq(builder)
    end
  end

  describe '#assistant' do
    it 'adds an assistant message' do
      builder.assistant('AI stands for Artificial Intelligence...')
      
      expect(builder.messages.size).to eq(1)
      message = builder.messages.first
      expect(message).to be_a(DSPy::LM::Message)
      expect(message.role).to eq(DSPy::LM::Message::Role::Assistant)
      expect(message.content).to eq('AI stands for Artificial Intelligence...')
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
      
      expect(builder.messages.size).to eq(4)
      
      expect(builder.messages[0].role).to eq(DSPy::LM::Message::Role::System)
      expect(builder.messages[0].content).to eq('You are a teacher')
      
      expect(builder.messages[1].role).to eq(DSPy::LM::Message::Role::User)
      expect(builder.messages[1].content).to eq('What is 2+2?')
      
      expect(builder.messages[2].role).to eq(DSPy::LM::Message::Role::Assistant)
      expect(builder.messages[2].content).to eq('2+2 equals 4')
      
      expect(builder.messages[3].role).to eq(DSPy::LM::Message::Role::User)
      expect(builder.messages[3].content).to eq('Why?')
    end
  end

  describe 'edge cases' do
    it 'handles empty content' do
      builder.user('')
      expect(builder.messages.size).to eq(1)
      expect(builder.messages.first.content).to eq('')
    end

    it 'handles nil content by converting to empty string' do
      builder.user(nil)
      expect(builder.messages.size).to eq(1)
      expect(builder.messages.first.content).to eq('')
    end

    it 'handles multiline content' do
      multiline = <<~TEXT
        Line 1
        Line 2
        Line 3
      TEXT
      
      builder.user(multiline.strip)
      expect(builder.messages.first.content).to eq("Line 1\nLine 2\nLine 3")
    end
  end

  describe '#to_h' do
    it 'converts messages to hash array for backward compatibility' do
      builder
        .system('You are a teacher')
        .user('What is 2+2?')
        .assistant('2+2 equals 4')
      
      expect(builder.to_h).to eq([
        { role: 'system', content: 'You are a teacher' },
        { role: 'user', content: 'What is 2+2?' },
        { role: 'assistant', content: '2+2 equals 4' }
      ])
    end
  end
end