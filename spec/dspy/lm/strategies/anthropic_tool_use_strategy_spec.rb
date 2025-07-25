# frozen_string_literal: true

require 'spec_helper'
require 'dspy/lm/adapters/anthropic_adapter'
require 'dspy/lm/strategies/anthropic_tool_use_strategy'

RSpec.describe DSPy::LM::Strategies::AnthropicToolUseStrategy do
  let(:adapter) { instance_double(DSPy::LM::AnthropicAdapter, model: 'claude-3-opus-20240229') }
  
  # Define a test signature
  class TestToolSignature < DSPy::Signature
    description "Test signature for tool use"
    
    input do
      const :question, String
    end
    
    output do
      const :answer, String
      const :confidence, Float
      const :steps, T::Array[String]
    end
  end
  
  let(:signature_class) { TestToolSignature }
  let(:strategy) { described_class.new(adapter, signature_class) }
  
  describe '#available?' do
    context 'with Anthropic adapter and Claude 3 model' do
      it 'returns true' do
        expect(strategy.available?).to be true
      end
    end
    
    context 'with non-Anthropic adapter' do
      let(:adapter) { instance_double(DSPy::LM::OpenAIAdapter, model: 'gpt-4') }
      
      it 'returns false' do
        expect(strategy.available?).to be false
      end
    end
    
    context 'with old Claude model' do
      let(:adapter) { instance_double(DSPy::LM::AnthropicAdapter, model: 'claude-2.1') }
      
      it 'returns false' do
        expect(strategy.available?).to be false
      end
    end
  end
  
  describe '#priority' do
    it 'returns 95 (higher than extraction strategy)' do
      expect(strategy.priority).to eq(95)
    end
  end
  
  describe '#name' do
    it 'returns anthropic_tool_use' do
      expect(strategy.name).to eq('anthropic_tool_use')
    end
  end
  
  describe '#prepare_request' do
    let(:messages) { [{ role: 'user', content: 'What is 2+2?' }] }
    let(:request_params) { {} }
    
    it 'adds tool definition to request params' do
      strategy.prepare_request(messages, request_params)
      
      expect(request_params).to have_key(:tools)
      expect(request_params[:tools]).to be_an(Array)
      expect(request_params[:tools].length).to eq(1)
      
      tool = request_params[:tools].first
      expect(tool[:name]).to eq('json_output')
      expect(tool[:description]).to include('JSON format')
      expect(tool[:input_schema]).to include(
        type: 'object',
        properties: {
          'answer' => { type: 'string' },
          'confidence' => { type: 'number' },
          'steps' => { type: 'array', items: { type: 'string' } }
        },
        required: ['answer', 'confidence', 'steps']
      )
    end
    
    it 'sets tool_choice to force tool use' do
      strategy.prepare_request(messages, request_params)
      
      expect(request_params[:tool_choice]).to eq({
        type: 'tool',
        name: 'json_output'
      })
    end
    
    it 'appends tool use instruction to user message' do
      strategy.prepare_request(messages, request_params)
      
      expect(messages.last[:content]).to include('Please use the json_output tool')
    end
  end
  
  describe '#extract_json' do
    context 'with tool use in metadata' do
      let(:response) do
        DSPy::LM::Response.new(
          content: 'I\'ll calculate 2+2 for you.',
          usage: nil,
          metadata: {
            tool_calls: [{
              id: 'call_123',
              name: 'json_output',
              input: {
                'answer' => '4',
                'confidence' => 1.0,
                'steps' => ['2 + 2 = 4']
              }
            }]
          }
        )
      end
      
      it 'extracts JSON from tool calls' do
        json = strategy.extract_json(response)
        expect(json).to be_a(String)
        
        parsed = JSON.parse(json)
        expect(parsed).to eq({
          'answer' => '4',
          'confidence' => 1.0,
          'steps' => ['2 + 2 = 4']
        })
      end
    end
    
    context 'with tool use in content' do
      let(:response) do
        DSPy::LM::Response.new(
          content: 'I\'ll help you. <tool_use><name>json_output</name><input>{"answer": "4", "confidence": 1.0, "steps": ["Add 2 + 2"]}</input></tool_use>',
          usage: nil,
          metadata: {}
        )
      end
      
      it 'extracts JSON from content' do
        json = strategy.extract_json(response)
        expect(json).to eq('{"answer": "4", "confidence": 1.0, "steps": ["Add 2 + 2"]}')
      end
    end
    
    context 'without tool use' do
      let(:response) do
        DSPy::LM::Response.new(
          content: 'The answer is 4.',
          usage: nil,
          metadata: {}
        )
      end
      
      it 'returns nil' do
        expect(strategy.extract_json(response)).to be_nil
      end
    end
  end
  
  describe '#handle_error' do
    context 'with tool-related error' do
      let(:error) { StandardError.new('Tool use failed: invalid tool schema') }
      
      it 'returns true to trigger fallback' do
        expect(strategy.handle_error(error)).to be true
      end
    end
    
    context 'with non-tool error' do
      let(:error) { StandardError.new('Network timeout') }
      
      it 'returns false' do
        expect(strategy.handle_error(error)).to be false
      end
    end
  end
end