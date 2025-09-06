# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::LM span tracking' do
  let(:api_key) { 'test-api-key' }
  let(:lm) { DSPy::LM.new('openai/gpt-4', api_key: api_key) }
  let(:messages) { DSPy::LM::MessageBuilder.new.user('Hello').instance_variable_get(:@messages) }
  
  before do
    DSPy::Context.clear!
    # Enable observability for logging to occur
    allow(DSPy::Observability).to receive(:enabled?).and_return(true)
    allow(DSPy).to receive(:log)
  end

  describe '#raw_chat' do
    let(:mock_adapter) { double('adapter') }
    let(:mock_response) do
      double('response',
        content: 'Test response',
        usage: double('usage', 
          input_tokens: 10,
          output_tokens: 20,
          total_tokens: 30
        ),
        metadata: double('metadata', model: 'gpt-4-0613')
      )
    end

    before do
      allow(lm).to receive(:adapter).and_return(mock_adapter)
      allow(mock_adapter).to receive(:chat).and_return(mock_response)
    end

    it 'wraps LLM calls in a span' do
      expect(DSPy).to receive(:log).with('span.start', hash_including(
        operation: 'llm.generate',
        trace_id: anything,
        span_id: anything,
        parent_span_id: nil,
        'gen_ai.system' => 'openai',
        'gen_ai.request.model' => 'gpt-4'
      ))

      expect(DSPy).to receive(:log).with('span.end', hash_including(
        trace_id: anything,
        span_id: anything,
        duration_ms: anything
      ))

      lm.raw_chat(messages)
    end

    # Skip temperature/max_tokens test since they're hardcoded in adapters currently

    it 'no longer logs span.attributes separately (now set directly on span)' do
      # This test verifies that we don't emit span.attributes events anymore
      # since attributes are now set directly on OpenTelemetry spans
      
      expect(DSPy).to receive(:log).with('span.start', anything)
      expect(DSPy).to receive(:log).with('span.end', anything)
      
      # Verify that span.attributes is NOT called
      expect(DSPy).not_to receive(:log).with('span.attributes', anything)

      lm.raw_chat(messages)
    end

    it 'maintains parent-child relationships for nested calls' do
      parent_span_id = nil
      child_span_id = nil
      
      allow(DSPy).to receive(:log) do |event, attrs|
        if event == 'span.start'
          if attrs[:operation] == 'parent.operation'
            parent_span_id = attrs[:span_id]
          elsif attrs[:operation] == 'llm.generate'
            child_span_id = attrs[:span_id]
            expect(attrs[:parent_span_id]).to eq(parent_span_id)
          end
        end
      end
      
      DSPy::Context.with_span(operation: 'parent.operation') do
        lm.raw_chat(messages)
      end
      
      expect(parent_span_id).not_to be_nil
      expect(child_span_id).not_to be_nil
    end

    context 'when usage data is not available' do
      let(:mock_response) do
        double('response',
          content: 'Test response',
          usage: nil,
          metadata: double('metadata', model: nil)
        )
      end

      it 'still completes the span without usage attributes' do
        expect(DSPy).to receive(:log).with('span.start', anything)
        expect(DSPy).not_to receive(:log).with('span.attributes', anything)
        expect(DSPy).to receive(:log).with('span.end', anything)

        lm.raw_chat(messages)
      end
    end
  end

  describe '#chat with signature' do
    let(:signature_class) do
      Class.new(DSPy::Signature) do
        input do
          const :question, String
        end
        
        output do
          const :answer, String
        end
      end
    end
    
    # For the signature test, we need to mock at a different level since 
    # StrategySelector needs a real adapter type

    it 'includes signature information in span' do
      # Create a proper Response object
      mock_response = DSPy::LM::Response.new(
        content: '{"answer": "42"}',
        usage: nil,
        metadata: DSPy::LM::ResponseMetadata.new(
          provider: 'openai',
          model: 'gpt-4-0613'
        )
      )
      
      allow(lm.adapter).to receive(:chat).and_return(mock_response)
      
      # Create a mock inference module
      inference_module = double('inference_module',
        signature_class: signature_class,
        system_signature: 'Answer the question',
        user_signature: 'What is life?',
        build_prompt_from_inputs: 'What is life?',
        process_response: { answer: '42' }
      )
      allow(inference_module).to receive(:user_signature).with(anything).and_return('What is life?')
      input_values = { question: 'What is life?' }
      
      expect(DSPy).to receive(:log).with('span.start', hash_including(
        operation: 'llm.generate',
        'dspy.signature' => signature_class.name
      ))
      
      allow(DSPy).to receive(:log).with('span.attributes', anything)
      allow(DSPy).to receive(:log).with('span.end', anything)

      lm.chat(inference_module, input_values)
    end
  end
end