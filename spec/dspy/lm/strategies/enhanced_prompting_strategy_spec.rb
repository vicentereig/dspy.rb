# frozen_string_literal: true

require 'spec_helper'
require 'dspy'
require 'dspy/signature'
require 'dspy/lm/response'
require 'dspy/lm/strategies/enhanced_prompting_strategy'

class SimpleTestSignature < DSPy::Signature
  description "Simple test signature"
  
  output do
    const :answer, String
    const :confidence, T.any(Float, NilClass)
  end
end

RSpec.describe DSPy::LM::Strategies::EnhancedPromptingStrategy do
  # Create a minimal test adapter
  class EnhancedPromptingTestAdapter < DSPy::LM::Adapter
    def chat(messages:, signature: nil, &block)
      # Stub implementation
    end
  end
  
  let(:adapter) { EnhancedPromptingTestAdapter.new(model: "test", api_key: "test-key") }
  let(:signature_class) { SimpleTestSignature }
  let(:strategy) { described_class.new(adapter, signature_class) }
  
  describe '#available?' do
    it 'is always available' do
      expect(strategy.available?).to be true
    end
  end
  
  describe '#priority' do
    it 'has medium priority' do
      expect(strategy.priority).to eq(50)
    end
  end
  
  describe '#name' do
    it 'returns the strategy name' do
      expect(strategy.name).to eq('enhanced_prompting')
    end
  end
  
  describe '#prepare_request' do
    let(:messages) { [{ role: 'user', content: 'Generate a simple answer' }] }
    let(:request_params) { {} }
    
    it 'enhances the user message with JSON instructions' do
      strategy.prepare_request(messages, request_params)
      
      expect(messages.last[:content]).to include('IMPORTANT: You must respond with valid JSON')
      expect(messages.last[:content]).to include('```json')
      expect(messages.last[:content]).to include('Required fields:')
    end
    
    it 'adds a system message if none exists' do
      strategy.prepare_request(messages, request_params)
      
      expect(messages.first[:role]).to eq('system')
      expect(messages.first[:content]).to include('helpful assistant')
    end
    
    context 'with existing system message' do
      let(:messages) do
        [
          { role: 'system', content: 'You are a test assistant' },
          { role: 'user', content: 'Generate a simple answer' }
        ]
      end
      
      it 'does not add another system message' do
        initial_count = messages.count { |m| m[:role] == 'system' }
        strategy.prepare_request(messages, request_params)
        final_count = messages.count { |m| m[:role] == 'system' }
        
        expect(final_count).to eq(initial_count)
      end
    end
  end
  
  describe '#extract_json' do
    context 'with markdown JSON block' do
      let(:response) do
        DSPy::LM::Response.new(
          content: <<~CONTENT,
          Here is the answer:
          ```json
          {"answer": "42", "confidence": 0.95}
          ```
          CONTENT
          usage: {}
        )
      end
      
      it 'extracts JSON from markdown block' do
        result = strategy.extract_json(response)
        expect(result).to eq('{"answer": "42", "confidence": 0.95}')
      end
    end
    
    context 'with plain JSON response' do
      let(:response) do
        DSPy::LM::Response.new(
          content: '{"answer": "42", "confidence": 0.95}',
          usage: {}
        )
      end
      
      it 'returns the JSON as-is' do
        result = strategy.extract_json(response)
        expect(result).to eq('{"answer": "42", "confidence": 0.95}')
      end
    end
    
    context 'with generic code block' do
      let(:response) do
        DSPy::LM::Response.new(
          content: <<~CONTENT,
          Here is the result:
          ```
          {"answer": "42", "confidence": 0.95}
          ```
          CONTENT
          usage: {}
        )
      end
      
      it 'extracts JSON from code block' do
        result = strategy.extract_json(response)
        expect(result).to eq('{"answer": "42", "confidence": 0.95}')
      end
    end
    
    context 'with JSON embedded in text' do
      let(:response) do
        DSPy::LM::Response.new(
          content: 'The result is {"answer": "42", "confidence": 0.95} as requested.',
          usage: {}
        )
      end
      
      it 'extracts JSON from text' do
        result = strategy.extract_json(response)
        expect(result).to eq('{"answer": "42", "confidence": 0.95}')
      end
    end
    
    context 'with no valid JSON' do
      let(:response) do
        DSPy::LM::Response.new(
          content: 'This is not JSON at all',
          usage: {}
        )
      end
      
      it 'returns nil' do
        result = strategy.extract_json(response)
        expect(result).to be_nil
      end
    end
    
    context 'with nil content' do
      let(:response) do
        DSPy::LM::Response.new(
          content: nil,
          usage: {}
        )
      end
      
      it 'returns nil' do
        result = strategy.extract_json(response)
        expect(result).to be_nil
      end
    end
  end
end