# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::ExecutionTrace do
  describe 'data structure' do
    let(:trace_data) do
      {
        trace_id: 'trace-123',
        event_name: 'llm.response',
        timestamp: Time.now,
        span_id: 'span-456',
        attributes: {
          'gen_ai.system' => 'openai',
          'gen_ai.request.model' => 'gpt-4',
          'gen_ai.usage.prompt_tokens' => 100,
          'gen_ai.usage.completion_tokens' => 50,
          'dspy.signature' => 'QuestionAnswering',
          prompt: 'What is 2+2?',
          response: '4'
        },
        metadata: {
          optimization_run_id: 'run-789',
          generation: 1,
          candidate_id: 'candidate-101'
        }
      }
    end

    it 'creates an immutable trace record' do
      trace = described_class.new(**trace_data)
      
      expect(trace.trace_id).to eq('trace-123')
      expect(trace.event_name).to eq('llm.response')
      expect(trace.timestamp).to eq(trace_data[:timestamp])
      expect(trace.span_id).to eq('span-456')
      expect(trace.attributes).to eq(trace_data[:attributes])
      expect(trace.metadata).to eq(trace_data[:metadata])
    end

    it 'is immutable' do
      trace = described_class.new(**trace_data)
      
      # Should be a Data class (immutable)
      expect(trace).to be_a(Data)
      
      # Attempting to modify should raise error
      expect { trace.trace_id = 'new-id' }.to raise_error(NoMethodError)
    end

    it 'freezes nested data structures' do
      trace = described_class.new(**trace_data)
      
      expect(trace.attributes).to be_frozen
      expect(trace.metadata).to be_frozen
    end

    it 'validates required fields' do
      expect { described_class.new(trace_id: 'test') }.to raise_error(ArgumentError)
      expect { described_class.new(event_name: 'test') }.to raise_error(ArgumentError)
      expect { described_class.new(timestamp: Time.now) }.to raise_error(ArgumentError)
    end
  end

  describe 'convenience methods' do
    let(:llm_trace) do
      described_class.new(
        trace_id: 'trace-llm',
        event_name: 'llm.response',
        timestamp: Time.now,
        span_id: 'span-llm',
        attributes: {
          'gen_ai.system' => 'openai',
          'gen_ai.request.model' => 'gpt-4o',
          'gen_ai.usage.total_tokens' => 150,
          prompt: 'What is the capital of France?',
          response: 'Paris'
        },
        metadata: { optimization_run_id: 'run-001' }
      )
    end

    let(:module_trace) do
      described_class.new(
        trace_id: 'trace-module',
        event_name: 'chain_of_thought.reasoning_complete',
        timestamp: Time.now,
        span_id: 'span-module',
        attributes: {
          'dspy.signature' => 'QuestionAnswering',
          'cot.reasoning_steps' => 3,
          'cot.reasoning_length' => 245,
          reasoning: 'Step 1: Identify the question...'
        },
        metadata: { optimization_run_id: 'run-001' }
      )
    end

    describe '#llm_trace?' do
      it 'returns true for LLM events' do
        expect(llm_trace.llm_trace?).to be(true)
      end

      it 'returns false for non-LLM events' do
        expect(module_trace.llm_trace?).to be(false)
      end
    end

    describe '#module_trace?' do
      it 'returns true for module events' do
        expect(module_trace.module_trace?).to be(true)
      end

      it 'returns false for non-module events' do
        expect(llm_trace.module_trace?).to be(false)
      end
    end

    describe '#token_usage' do
      it 'returns token usage for LLM traces' do
        expect(llm_trace.token_usage).to eq(150)
      end

      it 'returns 0 for non-LLM traces' do
        expect(module_trace.token_usage).to eq(0)
      end
    end

    describe '#to_h' do
      it 'returns trace as hash' do
        hash = llm_trace.to_h
        
        expect(hash).to include(
          trace_id: 'trace-llm',
          event_name: 'llm.response',
          span_id: 'span-llm'
        )
        expect(hash[:timestamp]).to be_a(Time)
        expect(hash[:attributes]).to be_a(Hash)
        expect(hash[:metadata]).to be_a(Hash)
      end
    end
  end
end