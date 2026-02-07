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
      
      expect(lm.instance_variable_get('@adapter')).to be_a(DSPy::OpenAI::LM::Adapters::OpenAIAdapter)
    end

    it 'creates Anthropic adapter for anthropic/ prefixed models' do
      lm = described_class.new('anthropic/claude-3-sonnet', api_key: 'test-key')
      
      expect(lm.instance_variable_get('@adapter')).to be_a(DSPy::Anthropic::LM::Adapters::AnthropicAdapter)
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
          metadata: DSPy::LM::ResponseMetadata.new(
            provider: 'test',
            model: 'test-model'
          )
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
        metadata: DSPy::LM::OpenAIResponseMetadata.new(
          provider: 'openai',
          model: 'gpt-4'
        )
      )
    end
    let(:signature_class) { TestSignature }
    let(:inference_module) do
      module_double = double('InferenceModule')
      prompt_double = double('Prompt')
      allow(prompt_double).to receive(:render_system_prompt).and_return('You are a helpful assistant')
      allow(prompt_double).to receive(:render_user_prompt).with(anything).and_return('Question: What is AI?\nAnswer:')
      allow(prompt_double).to receive(:to_h).and_return({})
      allow(prompt_double).to receive(:data_format).and_return(:json)
      allow(module_double).to receive(:signature_class).and_return(signature_class)
      allow(module_double).to receive(:prompt).and_return(prompt_double)
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
        metadata: DSPy::LM::OpenAIResponseMetadata.new(
          provider: 'openai',
          model: 'gpt-4'
        )
      )
    end
    let(:lm) { described_class.new('openai/gpt-4', api_key: 'test-key') }
    before do
      allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)
      mock_adapter.chat_response = mock_response
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

      it 'accepts symbol roles and string keys' do
        messages = [
          { role: :system, content: 'You are a helpful assistant' },
          { 'role' => :user, 'content' => 'What is 2+2?' }
        ]

        allow(mock_adapter).to receive(:chat).and_call_original

        lm.raw_chat(messages)

        expect(mock_adapter).to have_received(:chat) do |**args|
          expect(args[:messages]).to eq([
            { role: 'system', content: 'You are a helpful assistant' },
            { role: 'user', content: 'What is 2+2?' }
          ])
          expect(args[:signature]).to be_nil
        end
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

    context 'event emission' do
      after do
        # Clean up listeners after each test
        DSPy.events.clear_listeners
      end
      
      it 'emits lm.tokens event with timing and correlation data' do
        messages = [{ role: 'user', content: 'Test message' }]
        
        # Track emitted events
        events_emitted = []
        DSPy.events.subscribe('lm.tokens') do |event_name, attributes|
          events_emitted << { event: event_name, attributes: attributes }
        end
        
        allow(mock_adapter).to receive(:chat).and_call_original
        
        result = lm.raw_chat(messages)
        
        # Verify we got the lm.tokens event
        expect(events_emitted.size).to eq(1)
        
        token_event = events_emitted.first
        expect(token_event[:event]).to eq('lm.tokens')
        
        # Check token event attributes (standard lm.tokens structure)
        attributes = token_event[:attributes]
        expect(attributes[:input_tokens]).to eq(10)
        expect(attributes[:output_tokens]).to eq(20)
        expect(attributes[:total_tokens]).to eq(30)
        expect(attributes['gen_ai.system']).to eq('openai')
        expect(attributes['gen_ai.request.model']).to eq('gpt-4')
        expect(attributes['dspy.signature']).to eq('RawPrompt')
        
        # Check new timing and correlation attributes
        expect(attributes['request_id']).to be_a(String)
        expect(attributes['request_id'].length).to eq(16) # SecureRandom.hex(8)
        expect(attributes['duration']).to be_a(Float)
        expect(attributes['duration']).to be > 0
        
        expect(result).to eq('This is a raw response without JSON')
      end
      
      it 'handles responses without usage data gracefully' do
        messages = [{ role: 'user', content: 'Test message' }]
        
        # Create a response without usage data
        response_without_usage = DSPy::LM::Response.new(
          content: 'Response without usage',
          usage: nil,
          metadata: DSPy::LM::OpenAIResponseMetadata.new(
            provider: 'openai',
            model: 'gpt-4'
          )
        )
        mock_adapter.chat_response = response_without_usage
        
        # Track emitted events
        events_emitted = []
        DSPy.events.subscribe('lm.tokens') do |event_name, attributes|
          events_emitted << { event: event_name, attributes: attributes }
        end
        
        result = lm.raw_chat(messages)
        
        # No lm.tokens event should be emitted when there's no usage data
        expect(events_emitted).to be_empty
        expect(result).to eq('Response without usage')
      end
      
      it 'works with the example from JSON benchmark document' do
        messages = [{ role: 'user', content: 'Test message' }]
        
        # Simulate the pattern from the JSON benchmark document
        timing_data = {}
        
        DSPy.events.subscribe('lm.tokens') do |event_name, attributes|
          request_id = attributes['request_id']
          if request_id
            timing_data[request_id] = {
              start_time: Time.now - attributes['duration'], # Reconstruct start time
              duration: attributes['duration'],
              model: attributes['gen_ai.request.model'],
              tokens: attributes[:total_tokens] || 0
            }
          end
        end
        
        result = lm.raw_chat(messages)
        
        # Verify the timing data structure matches what users expect
        expect(timing_data.size).to eq(1)
        request_data = timing_data.values.first
        expect(request_data[:duration]).to be_a(Float)
        expect(request_data[:model]).to eq('gpt-4')  # Fixed: should be gpt-4, not test-model
        expect(request_data[:tokens]).to eq(30)
        expect(request_data[:start_time]).to be_a(Time)
        
        expect(result).to eq('This is a raw response without JSON')
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
        prompt_double = double('Prompt')
        allow(prompt_double).to receive(:render_system_prompt).and_return('You are a helpful assistant')
        allow(prompt_double).to receive(:render_user_prompt).with(anything).and_return('Question: What is AI?\nAnswer:')
        allow(prompt_double).to receive(:to_h).and_return({})
        allow(prompt_double).to receive(:data_format).and_return(:json)
        allow(module_double).to receive(:signature_class).and_return(signature_class_double)
        allow(module_double).to receive(:prompt).and_return(prompt_double)
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
