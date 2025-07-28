# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::Message do
  describe '.new' do
    it 'creates a message with required fields' do
      message = described_class.new(
        role: described_class::Role::System,
        content: 'You are a helpful assistant'
      )
      
      expect(message.role).to eq(described_class::Role::System)
      expect(message.content).to eq('You are a helpful assistant')
      expect(message.name).to be_nil
    end
    
    it 'creates a message with optional name field' do
      message = described_class.new(
        role: described_class::Role::User,
        content: 'Hello',
        name: 'user123'
      )
      
      expect(message.name).to eq('user123')
    end
  end
  
  describe '#to_h' do
    context 'without name' do
      let(:message) do
        described_class.new(
          role: described_class::Role::System,
          content: 'You are a helpful assistant'
        )
      end
      
      it 'returns hash with role and content' do
        expect(message.to_h).to eq({
          role: 'system',
          content: 'You are a helpful assistant'
        })
      end
    end
    
    context 'with name' do
      let(:message) do
        described_class.new(
          role: described_class::Role::User,
          content: 'Hello',
          name: 'user123'
        )
      end
      
      it 'includes name in the hash' do
        expect(message.to_h).to eq({
          role: 'user',
          content: 'Hello',
          name: 'user123'
        })
      end
    end
  end
  
  describe '#to_s' do
    context 'without name' do
      let(:message) do
        described_class.new(
          role: described_class::Role::Assistant,
          content: 'I can help with that'
        )
      end
      
      it 'formats as role: content' do
        expect(message.to_s).to eq('assistant: I can help with that')
      end
    end
    
    context 'with name' do
      let(:message) do
        described_class.new(
          role: described_class::Role::User,
          content: 'Hello',
          name: 'user123'
        )
      end
      
      it 'formats as role(name): content' do
        expect(message.to_s).to eq('user(user123): Hello')
      end
    end
  end
  
  describe DSPy::LM::Message::Role do
    it 'defines system, user, and assistant roles' do
      expect(described_class::System.serialize).to eq('system')
      expect(described_class::User.serialize).to eq('user')
      expect(described_class::Assistant.serialize).to eq('assistant')
    end
  end
end

RSpec.describe DSPy::LM::MessageFactory do
  describe '.create' do
    context 'with nil input' do
      it 'returns nil' do
        expect(described_class.create(nil)).to be_nil
      end
    end
    
    context 'with Message object' do
      let(:message) do
        DSPy::LM::Message.new(
          role: DSPy::LM::Message::Role::System,
          content: 'test'
        )
      end
      
      it 'returns the message as-is' do
        expect(described_class.create(message)).to eq(message)
      end
    end
    
    context 'with hash input' do
      context 'with symbol keys' do
        let(:hash) { { role: 'system', content: 'You are helpful' } }
        
        it 'creates a Message object' do
          message = described_class.create(hash)
          expect(message).to be_a(DSPy::LM::Message)
          expect(message.role).to eq(DSPy::LM::Message::Role::System)
          expect(message.content).to eq('You are helpful')
        end
      end
      
      context 'with string keys' do
        let(:hash) { { 'role' => 'user', 'content' => 'Hello' } }
        
        it 'creates a Message object' do
          message = described_class.create(hash)
          expect(message).to be_a(DSPy::LM::Message)
          expect(message.role).to eq(DSPy::LM::Message::Role::User)
          expect(message.content).to eq('Hello')
        end
      end
      
      context 'with name field' do
        let(:hash) { { role: 'user', content: 'Hello', name: 'user123' } }
        
        it 'includes the name in the Message object' do
          message = described_class.create(hash)
          expect(message.name).to eq('user123')
        end
      end
      
      context 'with invalid role' do
        let(:hash) { { role: 'invalid', content: 'test' } }
        
        it 'returns nil and logs debug message' do
          expect(DSPy.logger).to receive(:debug).with('Unknown message role: invalid')
          expect(described_class.create(hash)).to be_nil
        end
      end
      
      context 'with missing role' do
        let(:hash) { { content: 'test' } }
        
        it 'returns nil' do
          expect(described_class.create(hash)).to be_nil
        end
      end
      
      context 'with missing content' do
        let(:hash) { { role: 'system' } }
        
        it 'returns nil' do
          expect(described_class.create(hash)).to be_nil
        end
      end
    end
    
    context 'with object that responds to to_h' do
      let(:object) do
        double('MessageLike', to_h: { role: 'assistant', content: 'I can help' })
      end
      
      it 'converts to hash and creates Message' do
        message = described_class.create(object)
        expect(message).to be_a(DSPy::LM::Message)
        expect(message.role).to eq(DSPy::LM::Message::Role::Assistant)
        expect(message.content).to eq('I can help')
      end
    end
    
    context 'with invalid input type' do
      it 'returns nil for string input' do
        expect(described_class.create('invalid')).to be_nil
      end
      
      it 'returns nil for integer input' do
        expect(described_class.create(42)).to be_nil
      end
    end
  end
  
  describe '.create_many' do
    let(:messages) do
      [
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' },
        nil,
        { role: 'assistant', content: 'Assistant response' }
      ]
    end
    
    it 'creates multiple messages and filters out nils' do
      result = described_class.create_many(messages)
      
      expect(result.size).to eq(3)
      expect(result[0].role).to eq(DSPy::LM::Message::Role::System)
      expect(result[1].role).to eq(DSPy::LM::Message::Role::User)
      expect(result[2].role).to eq(DSPy::LM::Message::Role::Assistant)
    end
    
    it 'handles empty array' do
      expect(described_class.create_many([])).to eq([])
    end
  end
end