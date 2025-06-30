# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM do
  describe '#initialize' do
    it 'creates OpenAI adapter for openai/ prefixed models' do
      lm = described_class.new('openai/gpt-4', api_key: 'test-key')
      
      expect(lm.instance_variable_get('@adapter')).to be_a(DSPy::LM::OpenAIAdapter)
    end

    it 'creates Anthropic adapter for anthropic/ prefixed models' do
      lm = described_class.new('anthropic/claude-3-sonnet', api_key: 'test-key')
      
      expect(lm.instance_variable_get('@adapter')).to be_a(DSPy::LM::AnthropicAdapter)
    end

    it 'raises error for legacy model format without provider' do
      expect {
        described_class.new('gpt-3.5-turbo', api_key: 'test-key')
      }.to raise_error(ArgumentError, /model_id must include provider/)
    end

    it 'raises error for unsupported provider' do
      expect {
        described_class.new('unsupported/model', api_key: 'test-key')
      }.to raise_error(DSPy::LM::UnsupportedProviderError)
    end
  end

  describe '#chat' do
    let(:mock_adapter) { instance_double(DSPy::LM::OpenAIAdapter) }
    let(:mock_response) do
      DSPy::LM::Response.new(
        content: '{"answer": "test response"}',
        usage: { 'total_tokens' => 50 },
        metadata: { provider: 'openai', model: 'gpt-4' }
      )
    end
    let(:inference_module) do
      module_double = double('InferenceModule')
      signature_class_double = double('SignatureClass', name: 'TestSignature')
      allow(module_double).to receive(:signature_class).and_return(signature_class_double)
      allow(module_double).to receive(:system_signature).and_return('You are a helpful assistant')
      allow(module_double).to receive(:user_signature).with(anything).and_return('Question: What is AI?\nAnswer:')
      module_double
    end
    let(:input_values) { { question: 'What is AI?' } }

    before do
      allow(DSPy::LM::AdapterFactory).to receive(:create)
        .and_return(mock_adapter)
    end

    it 'delegates chat to the adapter' do
      lm = described_class.new('openai/gpt-4', api_key: 'test-key')
      
      expect(mock_adapter).to receive(:chat)
        .with(messages: [
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'Question: What is AI?\nAnswer:' }
        ])
        .and_return(mock_response)

      result = lm.chat(inference_module, input_values)
      expect(result).to eq({ 'answer' => 'test response' })
    end

    it 'passes block to adapter when provided' do
      lm = described_class.new('openai/gpt-4', api_key: 'test-key')
      block = proc { |chunk| puts chunk }
      
      expect(mock_adapter).to receive(:chat) do |**args, &passed_block|
        expect(passed_block).to eq(block)
        expect(args[:messages]).to eq([
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'Question: What is AI?\nAnswer:' }
        ])
        mock_response
      end

      result = lm.chat(inference_module, input_values, &block)
      expect(result).to eq({ 'answer' => 'test response' })
    end
  end

  describe 'private methods' do
    let(:lm) { described_class.new('openai/gpt-4', api_key: 'test-key') }

    describe '#parse_model_id' do
      it 'parses provider/model format correctly' do
        provider, model = lm.send(:parse_model_id, 'openai/gpt-4')
        expect(provider).to eq('openai')
        expect(model).to eq('gpt-4')
      end

      it 'raises error for legacy format without provider' do
        expect {
          lm.send(:parse_model_id, 'gpt-3.5-turbo')
        }.to raise_error(ArgumentError, /model_id must include provider/)
      end

      it 'handles complex model names with multiple slashes' do
        provider, model = lm.send(:parse_model_id, 'openai/gpt-4/custom-version')
        expect(provider).to eq('openai')
        expect(model).to eq('gpt-4/custom-version')
      end
    end

    describe '#build_messages' do
      let(:inference_module) do
        module_double = double('InferenceModule')
        signature_class_double = double('SignatureClass', name: 'TestSignature')
        allow(module_double).to receive(:signature_class).and_return(signature_class_double)
        allow(module_double).to receive(:system_signature).and_return('You are a helpful assistant')
        allow(module_double).to receive(:user_signature).with(anything).and_return('Question: What is AI?\nAnswer:')
        module_double
      end
      let(:input_values) { { question: 'What is AI?' } }

      it 'builds messages with system and user prompts' do
        messages = lm.send(:build_messages, inference_module, input_values)
        
        expect(messages).to eq([
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'Question: What is AI?\nAnswer:' }
        ])
      end
    end
  end
end
