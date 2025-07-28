# frozen_string_literal: true

require 'spec_helper'
require 'dspy/instrumentation/event_payloads'

RSpec.describe 'DSPy::Instrumentation Event Payloads' do
  describe DSPy::Instrumentation::LMRequestEvent do
    it 'creates a valid LM request event' do
      event = described_class.new(
        timestamp: '2024-01-01T00:00:00Z',
        duration_ms: 123.45,
        cpu_time_ms: 100.0,
        status: 'success',
        gen_ai_operation_name: 'chat',
        gen_ai_system: 'openai',
        gen_ai_request_model: 'gpt-4',
        signature_class: 'TestSignature',
        provider: 'openai',
        adapter_class: 'OpenAIAdapter',
        input_size: 1000
      )
      
      expect(event.timestamp).to eq('2024-01-01T00:00:00Z')
      expect(event.duration_ms).to eq(123.45)
      expect(event.status).to eq('success')
      expect(event.provider).to eq('openai')
    end
    
    it 'converts to hash with all fields' do
      event = described_class.new(
        timestamp: '2024-01-01T00:00:00Z',
        duration_ms: 123.45,
        cpu_time_ms: 100.0,
        status: 'error',
        gen_ai_operation_name: 'chat',
        gen_ai_system: 'openai',
        gen_ai_request_model: 'gpt-4',
        provider: 'openai',
        adapter_class: 'OpenAIAdapter',
        input_size: 1000,
        error_type: 'RuntimeError',
        error_message: 'Something went wrong'
      )
      
      hash = event.to_h
      expect(hash[:timestamp]).to eq('2024-01-01T00:00:00Z')
      expect(hash[:status]).to eq('error')
      expect(hash[:error_type]).to eq('RuntimeError')
      expect(hash[:error_message]).to eq('Something went wrong')
    end
  end
  
  describe DSPy::Instrumentation::LMTokensEvent do
    it 'creates a valid token usage event' do
      event = described_class.new(
        timestamp: '2024-01-01T00:00:00Z',
        status: 'success',
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        gen_ai_system: 'anthropic',
        gen_ai_request_model: 'claude-3-opus'
      )
      
      expect(event.input_tokens).to eq(100)
      expect(event.output_tokens).to eq(50)
      expect(event.total_tokens).to eq(150)
    end
  end
  
  describe DSPy::Instrumentation::ReactIterationEvent do
    it 'creates a valid ReAct iteration event' do
      event = described_class.new(
        timestamp: '2024-01-01T00:00:00Z',
        duration_ms: 500.0,
        cpu_time_ms: 450.0,
        status: 'success',
        iteration: 1,
        max_iterations: 5,
        history_length: 3,
        tools_used_so_far: ['search', 'calculator']
      )
      
      expect(event.iteration).to eq(1)
      expect(event.tools_used_so_far).to eq(['search', 'calculator'])
    end
  end
  
  describe DSPy::Instrumentation::ReactToolCallEvent do
    it 'creates a valid tool call event' do
      event = described_class.new(
        timestamp: '2024-01-01T00:00:00Z',
        duration_ms: 200.0,
        cpu_time_ms: 180.0,
        status: 'success',
        iteration: 2,
        tool_name: 'calculator',
        tool_input: { expression: '2 + 2' }
      )
      
      expect(event.tool_name).to eq('calculator')
      expect(event.tool_input).to eq({ expression: '2 + 2' })
    end
  end
  
  describe DSPy::Instrumentation::PredictValidationErrorEvent do
    it 'creates a validation error event' do
      event = described_class.new(
        timestamp: '2024-01-01T00:00:00Z',
        status: 'error',
        signature_class: 'TestSignature',
        module_name: 'Predict',
        field_name: 'answer',
        error_message: 'Field is required',
        retry_count: 2
      )
      
      expect(event.field_name).to eq('answer')
      expect(event.retry_count).to eq(2)
    end
  end
end