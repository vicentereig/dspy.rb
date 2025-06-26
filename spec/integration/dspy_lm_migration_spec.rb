# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::LM Migration Integration', type: :integration do
  describe 'adapter initialization' do
    it 'creates OpenAI adapter for openai/ prefixed models' do
      lm = DSPy::LM.new('openai/gpt-4', api_key: ENV['OPENAI_API_KEY'])

      expect(lm.instance_variable_get(:@adapter)).to be_a(DSPy::LM::OpenAIAdapter)
    end

    it 'creates Anthropic adapter for anthropic/ prefixed models' do
      lm = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: ENV['ANTHROPIC_API_KEY'])

      expect(lm.instance_variable_get(:@adapter)).to be_a(DSPy::LM::AnthropicAdapter)
    end

    it 'creates RubyLLM adapter for legacy model format' do
      lm = DSPy::LM.new('gpt-3.5-turbo', api_key: ENV['OPENAI_API_KEY'])

      expect(lm.instance_variable_get(:@adapter)).to be_a(DSPy::LM::RubyLLMAdapter)
    end
  end

  describe 'API backward compatibility' do
    let(:inference_module) do
      module_double = double('InferenceModule')
      allow(module_double).to receive(:signature_class).and_return(double('SignatureClass', name: 'TestSignature'))
      allow(module_double).to receive(:system_signature).and_return('You are a helpful assistant')
      allow(module_double).to receive(:user_signature).with(anything).and_return('Question: What is AI?\nAnswer:')
      module_double
    end

    let(:input_values) { { question: 'What is AI?' } }

    it 'preserves the original DSPy::LM API interface' do
      lm = DSPy::LM.new('openai/gpt-4', api_key: 'test-key')

      # Should respond to the expected public methods
      expect(lm).to respond_to(:chat)
      expect(lm.method(:chat).arity).to eq(2) # accepts 2 arguments (plus optional &block)
    end

    it 'maintains compatible initialization signature' do
      expect { DSPy::LM.new('openai/gpt-4', api_key: 'test-key') }.not_to raise_error
      expect { DSPy::LM.new('anthropic/claude-3-sonnet', api_key: 'test-key') }.not_to raise_error
      expect { DSPy::LM.new('gpt-3.5-turbo', api_key: 'test-key') }.not_to raise_error
    end

    it 'maintains model_id parsing compatibility' do
      lm_openai = DSPy::LM.new('openai/gpt-4', api_key: 'test-key')
      lm_anthropic = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: 'test-key')
      lm_legacy = DSPy::LM.new('gpt-3.5-turbo', api_key: 'test-key')

      expect(lm_openai.instance_variable_get(:@provider)).to eq('openai')
      expect(lm_openai.instance_variable_get(:@model)).to eq('gpt-4')

      expect(lm_anthropic.instance_variable_get(:@provider)).to eq('anthropic')
      expect(lm_anthropic.instance_variable_get(:@model)).to eq('claude-3-sonnet')

      expect(lm_legacy.instance_variable_get(:@provider)).to eq('ruby_llm')
      expect(lm_legacy.instance_variable_get(:@model)).to eq('gpt-3.5-turbo')
    end
  end

  describe 'adapter delegation' do
    let(:mock_adapter) { double('Adapter') }
    let(:mock_response) do
      DSPy::LM::Response.new(
        content: '{"answer": "test response"}',
        usage: { 'total_tokens' => 50 },
        metadata: { provider: 'openai', model: 'gpt-4' }
      )
    end

    let(:inference_module) do
      module_double = double('InferenceModule')
      allow(module_double).to receive(:signature_class).and_return(double('SignatureClass', name: 'TestSignature'))
      allow(module_double).to receive(:system_signature).and_return('You are a helpful assistant')
      allow(module_double).to receive(:user_signature).with(anything).and_return('Question: What is AI?\nAnswer:')
      module_double
    end

    let(:input_values) { { question: 'What is AI?' } }

    before do
      allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)
    end

    it 'properly delegates chat calls to the adapter' do
      expect(mock_adapter).to receive(:chat)
        .with(messages: [
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'Question: What is AI?\nAnswer:' }
        ])
        .and_return(mock_response)

      lm = DSPy::LM.new('openai/gpt-4', api_key: 'test-key')
      result = lm.chat(inference_module, input_values)

      expect(result).to eq({ 'answer' => 'test response' })
    end

    it 'supports streaming with block parameter' do
      block = proc { |chunk| puts chunk }

      expect(mock_adapter).to receive(:chat) do |**args, &passed_block|
        expect(passed_block).to eq(block)
        expect(args[:messages]).to eq([
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'Question: What is AI?\nAnswer:' }
        ])
        mock_response
      end

      lm = DSPy::LM.new('openai/gpt-4', api_key: 'test-key')
      result = lm.chat(inference_module, input_values, &block)

      expect(result).to eq({ 'answer' => 'test response' })
    end
  end

  describe 'error handling' do
    it 'raises meaningful errors for unsupported providers' do
      expect {
        DSPy::LM.new('unsupported/model', api_key: 'test-key')
      }.to raise_error(DSPy::LM::UnsupportedProviderError, /Unsupported provider: unsupported/)
    end
  end
end
