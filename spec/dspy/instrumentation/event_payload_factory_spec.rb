# frozen_string_literal: true

require 'spec_helper'
require 'dspy/instrumentation/event_payload_factory'

RSpec.describe DSPy::Instrumentation::EventPayloadFactory do
  describe '.create_event' do
    context 'with LM request event' do
      it 'creates LMRequestEvent struct from hash payload' do
        payload = {
          gen_ai_operation_name: 'chat',
          gen_ai_system: 'openai',
          gen_ai_request_model: 'gpt-4',
          provider: 'openai',
          adapter_class: 'OpenAIAdapter',
          input_size: 1000
        }
        
        event = described_class.create_event('dspy.lm.request', payload)
        
        expect(event).to be_a(DSPy::Instrumentation::LMRequestEvent)
        expect(event.gen_ai_operation_name).to eq('chat')
        expect(event.provider).to eq('openai')
        expect(event.input_size).to eq(1000)
        expect(event.timestamp).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(event.status).to eq('success')
      end
      
      it 'handles error payloads' do
        payload = {
          gen_ai_operation_name: 'chat',
          gen_ai_system: 'openai',
          gen_ai_request_model: 'gpt-4',
          provider: 'openai',
          adapter_class: 'OpenAIAdapter',
          input_size: 1000,
          status: 'error',
          error_type: 'TimeoutError',
          error_message: 'Request timed out',
          duration_ms: 30000.0,
          cpu_time_ms: 100.0
        }
        
        event = described_class.create_event('dspy.lm.request', payload)
        
        expect(event.status).to eq('error')
        expect(event.error_type).to eq('TimeoutError')
        expect(event.error_message).to eq('Request timed out')
        expect(event.duration_ms).to eq(30000.0)
      end
    end
    
    context 'with LM tokens event' do
      it 'creates LMTokensEvent struct' do
        payload = {
          input_tokens: 100,
          output_tokens: 50,
          total_tokens: 150,
          gen_ai_system: 'anthropic',
          gen_ai_request_model: 'claude-3-opus',
          signature_class: 'TestSignature'
        }
        
        event = described_class.create_event('dspy.lm.tokens', payload)
        
        expect(event).to be_a(DSPy::Instrumentation::LMTokensEvent)
        expect(event.input_tokens).to eq(100)
        expect(event.output_tokens).to eq(50)
        expect(event.total_tokens).to eq(150)
        expect(event.signature_class).to eq('TestSignature')
      end
    end
    
    context 'with ReAct events' do
      it 'creates ReactIterationEvent struct' do
        payload = {
          iteration: 2,
          max_iterations: 5,
          history_length: 4,
          tools_used_so_far: ['search', 'calculator']
        }
        
        event = described_class.create_event('dspy.react.iteration', payload)
        
        expect(event).to be_a(DSPy::Instrumentation::ReactIterationEvent)
        expect(event.iteration).to eq(2)
        expect(event.tools_used_so_far).to eq(['search', 'calculator'])
      end
      
      it 'creates ReactToolCallEvent struct' do
        payload = {
          iteration: 3,
          tool_name: 'web_search',
          tool_input: { query: 'DSPy documentation' }
        }
        
        event = described_class.create_event('dspy.react.tool_call', payload)
        
        expect(event).to be_a(DSPy::Instrumentation::ReactToolCallEvent)
        expect(event.tool_name).to eq('web_search')
        expect(event.tool_input).to eq({ query: 'DSPy documentation' })
      end
      
      it 'creates ReactIterationCompleteEvent struct' do
        payload = {
          iteration: 2,
          thought: 'I need to search for information',
          action: 'search',
          action_input: 'DSPy library',
          observation: 'Found relevant documentation',
          tools_used: ['search']
        }
        
        event = described_class.create_event('dspy.react.iteration_complete', payload)
        
        expect(event).to be_a(DSPy::Instrumentation::ReactIterationCompleteEvent)
        expect(event.thought).to eq('I need to search for information')
        expect(event.action).to eq('search')
      end
    end
    
    context 'with validation error event' do
      it 'creates PredictValidationErrorEvent struct' do
        payload = {
          signature_class: 'QASignature',
          module_name: 'ChainOfThought',
          field_name: 'answer',
          error_message: 'Answer must not be empty',
          retry_count: 1
        }
        
        event = described_class.create_event('dspy.predict.validation_error', payload)
        
        expect(event).to be_a(DSPy::Instrumentation::PredictValidationErrorEvent)
        expect(event.field_name).to eq('answer')
        expect(event.retry_count).to eq(1)
      end
    end
    
    context 'with unknown event' do
      it 'returns original payload hash' do
        payload = { some: 'data' }
        
        event = described_class.create_event('unknown.event', payload)
        
        expect(event).to eq(payload)
        expect(event).to be_a(Hash)
      end
    end
    
    context 'with missing fields' do
      it 'provides defaults for required fields' do
        event = described_class.create_event('dspy.lm.request', {})
        
        expect(event).to be_a(DSPy::Instrumentation::LMRequestEvent)
        expect(event.gen_ai_operation_name).to eq('unknown')
        expect(event.provider).to eq('unknown')
        expect(event.input_size).to eq(0)
        expect(event.duration_ms).to eq(0.0)
      end
    end
  end
end