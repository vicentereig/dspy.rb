# frozen_string_literal: true

require 'spec_helper'
require 'dspy/signature'

class TestSignature < DSPy::Signature
  description "Test signature"
  
  output do
    const :answer, String
  end
end

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
    # Create a test adapter that inherits from the base adapter
    class LMSpecTestAdapter < DSPy::LM::Adapter
      attr_accessor :chat_response
      
      def chat(messages:, signature: nil, **kwargs, &block)
        @chat_response || DSPy::LM::Response.new(
          content: '{"answer": "test response"}',
          usage: { 'total_tokens' => 50 },
          metadata: { provider: 'test', model: 'test-model' }
        )
      end
    end
    
    let(:mock_adapter) { LMSpecTestAdapter.new(model: 'test-model', api_key: 'test-key') }
    let(:mock_response) do
      DSPy::LM::Response.new(
        content: '{"answer": "test response"}',
        usage: DSPy::LM::Usage.new(
          input_tokens: 20,
          output_tokens: 30,
          total_tokens: 50
        ),
        metadata: { provider: 'openai', model: 'gpt-4' }
      )
    end
    let(:signature_class) { TestSignature }
    let(:inference_module) do
      module_double = double('InferenceModule')
      allow(module_double).to receive(:signature_class).and_return(signature_class)
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
      
      # Spy on the adapter's chat method
      allow(mock_adapter).to receive(:chat).and_call_original
      mock_adapter.chat_response = mock_response

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

    it 'passes block to adapter when provided' do
      lm = described_class.new('openai/gpt-4', api_key: 'test-key')
      block = proc { |chunk| puts chunk }
      
      # Spy on the chat method to capture the block
      called_with_block = nil
      allow(mock_adapter).to receive(:chat) do |**args, &passed_block|
        called_with_block = passed_block
        mock_response
      end

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

  describe '#raw_chat' do
    # Use the same test adapter from above
    let(:mock_adapter) { LMSpecTestAdapter.new(model: 'test-model', api_key: 'test-key') }
    let(:mock_response) do
      DSPy::LM::Response.new(
        content: 'This is a raw response without JSON',
        usage: DSPy::LM::Usage.new(
          input_tokens: 10,
          output_tokens: 20,
          total_tokens: 30
        ),
        metadata: { provider: 'openai', model: 'gpt-4' }
      )
    end
    let(:lm) { described_class.new('openai/gpt-4', api_key: 'test-key') }
    let(:captured_events) { [] }

    before do
      allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)
      mock_adapter.chat_response = mock_response
      
      # Capture instrumentation events
      DSPy::Instrumentation.subscribe do |event|
        captured_events << event
      end
    end

    after do
      captured_events.clear
    end

    context 'with array format' do
      it 'sends raw messages to the adapter' do
        messages = [
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'What is 2+2?' }
        ]
        
        allow(mock_adapter).to receive(:chat).and_call_original
        
        result = lm.raw_chat(messages)
        
        expect(mock_adapter).to have_received(:chat) do |**args|
          # Messages are now converted to hash format for adapters
          expect(args[:messages]).to eq(messages)
          expect(args[:signature]).to be_nil
        end
        expect(result).to eq('This is a raw response without JSON')
      end
    end

    context 'with DSL builder' do
      it 'builds messages using the DSL' do
        allow(mock_adapter).to receive(:chat).and_call_original
        
        result = lm.raw_chat do |m|
          m.system 'You are a math tutor'
          m.user 'Explain calculus'
        end
        
        expect(mock_adapter).to have_received(:chat) do |**args|
          expect(args[:messages]).to eq([
            { role: 'system', content: 'You are a math tutor' },
            { role: 'user', content: 'Explain calculus' }
          ])
          expect(args[:signature]).to be_nil
        end
        expect(result).to eq('This is a raw response without JSON')
      end

      it 'supports assistant messages in the DSL' do
        allow(mock_adapter).to receive(:chat).and_call_original
        
        result = lm.raw_chat do |m|
          m.user 'What is AI?'
          m.assistant 'AI stands for Artificial Intelligence...'
          m.user 'Tell me more'
        end
        
        expect(mock_adapter).to have_received(:chat) do |**args|
          expect(args[:messages].length).to eq(3)
          expect(args[:messages][1][:role]).to eq('assistant')
        end
      end
    end

    context 'instrumentation' do
      it 'emits dspy.lm.request event with RawPrompt signature_class' do
        lm.raw_chat([{ role: 'user', content: 'Hello' }])
        
        request_events = captured_events.select { |e| e.id == 'dspy.lm.request' }
        expect(request_events.length).to eq(1)
        
        event = request_events.first
        expect(event.payload[:signature_class]).to eq('RawPrompt')
        expect(event.payload[:gen_ai_operation_name]).to eq('chat')
        expect(event.payload[:provider]).to eq('openai')
      end

      it 'emits dspy.lm.tokens event with token usage' do
        lm.raw_chat([{ role: 'user', content: 'Hello' }])
        
        token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
        expect(token_events.length).to eq(1)
        
        event = token_events.first
        expect(event.payload[:signature_class]).to eq('RawPrompt')
        expect(event.payload[:total_tokens]).to eq(30)
        expect(event.payload[:input_tokens]).to eq(10)
        expect(event.payload[:output_tokens]).to eq(20)
      end

      it 'does NOT emit dspy.lm.response.parsed event' do
        lm.raw_chat([{ role: 'user', content: 'Hello' }])
        
        parsed_events = captured_events.select { |e| e.id == 'dspy.lm.response.parsed' }
        expect(parsed_events).to be_empty
      end
    end

    context 'streaming' do
      it 'passes block to adapter for streaming' do
        chunks = []
        block = proc { |chunk| chunks << chunk }
        
        allow(mock_adapter).to receive(:chat) do |**args, &passed_block|
          # Simulate streaming
          passed_block.call('chunk1') if passed_block
          passed_block.call('chunk2') if passed_block
          mock_response
        end
        
        result = lm.raw_chat([{ role: 'user', content: 'Stream this' }], &block)
        
        expect(chunks).to eq(['chunk1', 'chunk2'])
        expect(result).to eq('This is a raw response without JSON')
      end
    end

    context 'error handling' do
      it 'validates message format' do
        expect {
          lm.raw_chat('invalid format')
        }.to raise_error(ArgumentError, /messages must be an array/)
      end

      it 'validates each message has required fields' do
        expect {
          lm.raw_chat([{ content: 'missing role' }])
        }.to raise_error(ArgumentError, /must have :role and :content/)
      end

      it 'validates role is valid' do
        expect {
          lm.raw_chat([{ role: 'invalid', content: 'test' }])
        }.to raise_error(ArgumentError, /Invalid role/)
      end
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
        
        expect(messages.size).to eq(2)
        
        expect(messages[0]).to be_a(DSPy::LM::Message)
        expect(messages[0].role).to eq(DSPy::LM::Message::Role::System)
        expect(messages[0].content).to eq('You are a helpful assistant')
        
        expect(messages[1]).to be_a(DSPy::LM::Message)
        expect(messages[1].role).to eq(DSPy::LM::Message::Role::User)
        expect(messages[1].content).to eq('Question: What is AI?\nAnswer:')
      end
    end
  end
end
