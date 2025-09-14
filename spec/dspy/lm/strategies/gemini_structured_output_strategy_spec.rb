# frozen_string_literal: true

require 'spec_helper'
require 'dspy/lm/adapters/gemini_adapter'
require 'dspy/lm/strategies/gemini_structured_output_strategy'

RSpec.describe DSPy::LM::Strategies::GeminiStructuredOutputStrategy do
  # Create test adapter classes for testing
  class TestGeminiAdapter < DSPy::LM::GeminiAdapter
    attr_reader :model, :structured_outputs_enabled
    
    def initialize(model:, structured_outputs: false, api_key: "test")
      @model = model
      @structured_outputs_enabled = structured_outputs
      # Don't call super to avoid real API setup
      @api_key = api_key
    end
    
    def chat(messages:, signature: nil, **extra_params, &block)
      # Stub implementation
    end
  end
  
  class TestOpenAIAdapter < DSPy::LM::Adapter
    attr_reader :model
    
    def initialize(model:, api_key: "test")
      @model = model
      @api_key = api_key
    end
    
    def chat(messages:, signature: nil, **extra_params, &block)
      # Stub implementation
    end
  end
  

  let(:adapter) { TestGeminiAdapter.new(model: 'gemini-1.5-pro', structured_outputs: true) }
  let(:signature_class) do
    Class.new(DSPy::Signature) do
      description "Test signature"
      
      output do
        const :result, String, description: "Test result"
      end
    end
  end
  let(:strategy) { described_class.new(adapter, signature_class) }

  describe '#available?' do
    context 'with GeminiAdapter' do
      before do
        allow(DSPy::LM::Adapters::Gemini::SchemaConverter).to receive(:supports_structured_outputs?).and_return(true)
      end
      
      it 'returns true when structured outputs are enabled and model is supported' do
        expect(strategy.available?).to eq(true)
      end
      
      it 'returns false when structured outputs are not enabled' do
        adapter = TestGeminiAdapter.new(model: 'gemini-1.5-pro', structured_outputs: false)
        strategy = described_class.new(adapter, signature_class)
        expect(strategy.available?).to eq(false)
      end
      
      it 'returns false when model is not supported' do
        allow(DSPy::LM::Adapters::Gemini::SchemaConverter).to receive(:supports_structured_outputs?).and_return(false)
        expect(strategy.available?).to eq(false)
      end
    end
    
    context 'with non-Gemini adapter' do
      let(:adapter) { TestOpenAIAdapter.new(model: 'gpt-4') }
      let(:strategy) { described_class.new(adapter, signature_class) }
      
      it 'returns false' do
        expect(strategy.available?).to eq(false)
      end
    end
  end

  describe '#priority' do
    it 'returns high priority for native structured outputs' do
      expect(strategy.priority).to eq(100)
    end
  end

  describe '#name' do
    it 'returns the strategy name' do
      expect(strategy.name).to eq('gemini_structured_output')
    end
  end

  describe '#prepare_request' do
    let(:messages) { [{ role: 'user', content: 'Test message' }] }
    let(:request_params) { {} }
    let(:converted_schema) do
      {
        type: 'object',
        properties: { result: { type: 'string' } },
        required: ['result']
      }
    end
    
    before do
      allow(DSPy::LM::Adapters::Gemini::SchemaConverter).to receive(:to_gemini_format)
        .with(signature_class)
        .and_return(converted_schema)
    end
    
    it 'adds generation_config to request params' do
      strategy.prepare_request(messages, request_params)
      
      expect(request_params[:generation_config]).to eq({
        response_mime_type: 'application/json',
        response_json_schema: converted_schema
      })
    end
    
    it 'does not modify messages' do
      original_messages = messages.dup
      strategy.prepare_request(messages, request_params)
      
      expect(messages).to eq(original_messages)
    end
  end

  describe '#extract_json' do
    context 'with valid JSON response' do
      let(:response) do
        DSPy::LM::Response.new(
          content: '{"result": "success"}',
          metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test')
        )
      end
      
      it 'returns the response content directly' do
        expect(strategy.extract_json(response)).to eq('{"result": "success"}')
      end
    end
    
    context 'with empty response' do
      let(:response) do
        DSPy::LM::Response.new(
          content: '',
          metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test')
        )
      end
      
      it 'returns empty string' do
        expect(strategy.extract_json(response)).to eq('')
      end
    end
    
    context 'with nil-like response' do
      let(:response) do
        DSPy::LM::Response.new(
          content: "",
          metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test')
        )
      end
      
      # Test the extract_json logic directly for nil handling
      it 'handles nil content gracefully' do
        allow(response).to receive(:content).and_return(nil)
        expect(strategy.extract_json(response)).to be_nil
      end
    end
  end

  describe '#handle_error' do
    context 'with Gemini-specific structured output error' do
      let(:error) { StandardError.new('Invalid schema format') }
      
      it 'handles the error and returns true' do
        expect(DSPy.logger).to receive(:debug).with(/Gemini structured output failed/)
        expect(strategy.handle_error(error)).to eq(true)
      end
    end
    
    context 'with generation_config error' do
      let(:error) { StandardError.new('generation_config parameter invalid') }
      
      it 'handles the error and returns true' do
        expect(DSPy.logger).to receive(:debug).with(/Gemini structured output failed/)
        expect(strategy.handle_error(error)).to eq(true)
      end
    end
    
    context 'with unrelated error' do
      let(:error) { StandardError.new('Network timeout') }
      
      it 'does not handle the error and returns false' do
        expect(strategy.handle_error(error)).to eq(false)
      end
    end
  end
end