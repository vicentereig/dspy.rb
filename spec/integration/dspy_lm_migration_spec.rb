# frozen_string_literal: true

require 'spec_helper'
require 'dspy/signature'

class TestMigrationSignature < DSPy::Signature
  description "Test signature"
  
  output do
    const :answer, String
  end
end

RSpec.describe 'DSPy::LM Migration Integration', type: :integration do
  describe 'adapter initialization' do
    it 'creates OpenAI adapter for openai/ prefixed models' do
      lm = DSPy::LM.new('openai/gpt-4', api_key: ENV['OPENAI_API_KEY'])

      expect(lm.instance_variable_get(:@adapter)).to be_a(DSPy::OpenAI::LM::Adapters::OpenAIAdapter)
    end

    it 'creates Anthropic adapter for anthropic/ prefixed models' do
      lm = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: ENV['ANTHROPIC_API_KEY'])

      expect(lm.instance_variable_get(:@adapter)).to be_a(DSPy::Anthropic::LM::Adapters::AnthropicAdapter)
    end

    it 'raises error for legacy model format without provider' do
      expect {
        DSPy::LM.new('gpt-3.5-turbo', api_key: ENV['OPENAI_API_KEY'])
      }.to raise_error(ArgumentError, /model_id must include provider/)
    end
  end

  describe 'API backward compatibility' do
    let(:inference_module) do
      module_double = double('InferenceModule')
      prompt_double = double('Prompt')
      allow(prompt_double).to receive(:render_system_prompt).and_return('You are a helpful assistant')
      allow(prompt_double).to receive(:render_user_prompt).with(anything).and_return('Question: What is AI?\nAnswer:')
      allow(prompt_double).to receive(:to_h).and_return({})
      allow(module_double).to receive(:signature_class).and_return(double('SignatureClass', name: 'TestSignature'))
      allow(module_double).to receive(:prompt).and_return(prompt_double)
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

    it 'maintains compatible initialization signature for supported providers' do
      expect { DSPy::LM.new('openai/gpt-4', api_key: 'test-key') }.not_to raise_error
      expect { DSPy::LM.new('anthropic/claude-3-sonnet', api_key: 'test-key') }.not_to raise_error
    end

    it 'raises error for legacy format without provider' do
      expect { DSPy::LM.new('gpt-3.5-turbo', api_key: 'test-key') }.to raise_error(ArgumentError, /model_id must include provider/)
    end

    it 'maintains model_id parsing compatibility for supported providers' do
      lm_openai = DSPy::LM.new('openai/gpt-4', api_key: 'test-key')
      lm_anthropic = DSPy::LM.new('anthropic/claude-3-sonnet', api_key: 'test-key')

      expect(lm_openai.instance_variable_get(:@provider)).to eq('openai')
      expect(lm_openai.instance_variable_get(:@model)).to eq('gpt-4')

      expect(lm_anthropic.instance_variable_get(:@provider)).to eq('anthropic')
      expect(lm_anthropic.instance_variable_get(:@model)).to eq('claude-3-sonnet')
    end
  end

  describe 'adapter delegation' do
    # Create a test adapter that inherits from the base adapter
    class TestMigrationAdapter < DSPy::LM::Adapter
      attr_accessor :chat_response
      
      def chat(messages:, signature: nil, **kwargs, &block)
        @chat_response || DSPy::LM::Response.new(
          content: '{"answer": "test response"}',
          usage: DSPy::LM::Usage.new(
          input_tokens: 20,
          output_tokens: 30,
          total_tokens: 50
        ),
          metadata: DSPy::LM::ResponseMetadata.new(
            provider: 'test',
            model: 'test-model'
          )
        )
      end
    end
    
    let(:mock_adapter) { TestMigrationAdapter.new(model: 'test-model', api_key: 'test-key') }
    let(:mock_response) do
      DSPy::LM::Response.new(
        content: '{"answer": "test response"}',
        usage: DSPy::LM::Usage.new(
          input_tokens: 20,
          output_tokens: 30,
          total_tokens: 50
        ),
        metadata: DSPy::LM::OpenAIResponseMetadata.new(
          provider: 'openai',
          model: 'gpt-4'
        )
      )
    end

    let(:signature_class) { TestMigrationSignature }
    let(:inference_module) do
      module_double = double('InferenceModule')
      prompt_double = double('Prompt')
      allow(prompt_double).to receive(:render_system_prompt).and_return('You are a helpful assistant')
      allow(prompt_double).to receive(:render_user_prompt).with(anything).and_return('Question: What is AI?\nAnswer:')
      allow(prompt_double).to receive(:to_h).and_return({})
      allow(module_double).to receive(:signature_class).and_return(signature_class)
      allow(module_double).to receive(:prompt).and_return(prompt_double)
      allow(module_double).to receive(:system_signature).and_return('You are a helpful assistant')
      allow(module_double).to receive(:user_signature).with(anything).and_return('Question: What is AI?\nAnswer:')
      module_double
    end

    let(:input_values) { { question: 'What is AI?' } }

    before do
      allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)
    end

    it 'properly delegates chat calls to the adapter' do
      # Spy on the adapter's chat method
      allow(mock_adapter).to receive(:chat).and_call_original
      mock_adapter.chat_response = mock_response

      lm = DSPy::LM.new('openai/gpt-4', api_key: 'test-key')
      result = lm.chat(inference_module, input_values)
      
      # Verify the adapter was called with messages (enhanced by strategy)
      expect(mock_adapter).to have_received(:chat) do |**args|
        # The strategy may enhance the messages, so check the basics
        expect(args[:messages].first[:role]).to eq('system')
        expect(args[:messages].last[:role]).to eq('user')
        expect(args[:messages].last[:content]).to include('Question: What is AI?')
        expect(args[:signature]).to eq(signature_class)
      end

      expect(result).to eq({ 'answer' => 'test response' })
    end

    it 'supports streaming with block parameter' do
      block = proc { |chunk| puts chunk }

      # Spy on the chat method to capture the block
      called_with_block = nil
      allow(mock_adapter).to receive(:chat) do |**args, &passed_block|
        called_with_block = passed_block
        mock_response
      end

      lm = DSPy::LM.new('openai/gpt-4', api_key: 'test-key')
      result = lm.chat(inference_module, input_values, &block)
      
      # Verify the block was passed through
      expect(called_with_block).to eq(block)
      expect(mock_adapter).to have_received(:chat) do |**args|
        # The strategy may enhance the messages, so check the basics
        expect(args[:messages].first[:role]).to eq('system')
        expect(args[:messages].last[:role]).to eq('user')
        expect(args[:messages].last[:content]).to include('Question: What is AI?')
        expect(args[:signature]).to eq(signature_class)
      end

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
