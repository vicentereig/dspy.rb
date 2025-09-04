# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::TraceCollector do
  describe 'initialization' do
    it 'creates a new collector with empty traces' do
      collector = described_class.new
      expect(collector.traces).to be_empty
      expect(collector.collected_count).to eq(0)
    end
  end

  describe 'event subscription' do
    let(:collector) { described_class.new }

    it 'includes SubscriberMixin' do
      expect(described_class.included_modules).to include(DSPy::Events::SubscriberMixin)
    end

    it 'subscribes to LLM and module events' do
      expect(collector.class.subscriptions).not_to be_empty
    end
  end

  describe '#collect_trace' do
    let(:collector) { described_class.new }
    let(:llm_event_data) do
      {
        'trace_id' => 'trace-123',
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'span_id' => 'span-456',
        'attributes' => {
          'gen_ai.system' => 'openai',
          'gen_ai.request.model' => 'gpt-4',
          prompt: 'What is 2+2?',
          response: '4'
        },
        'metadata' => {
          optimization_run_id: 'run-789'
        }
      }
    end

    it 'collects traces from event data' do
      collector.collect_trace('llm.response', llm_event_data)
      
      expect(collector.collected_count).to eq(1)
      expect(collector.traces.size).to eq(1)
      
      trace = collector.traces.first
      expect(trace).to be_a(DSPy::Teleprompt::GEPA::ExecutionTrace)
      expect(trace.trace_id).to eq('trace-123')
      expect(trace.event_name).to eq('llm.response')
    end

    it 'handles missing trace_id by generating one' do
      event_data = llm_event_data.except('trace_id')
      
      collector.collect_trace('llm.response', event_data)
      
      trace = collector.traces.first
      expect(trace.trace_id).to match(/^gepa-trace-\h{8}$/)
    end

    it 'filters duplicate traces by trace_id' do
      collector.collect_trace('llm.response', llm_event_data)
      collector.collect_trace('llm.response', llm_event_data) # Same trace_id
      
      expect(collector.collected_count).to eq(1)
      expect(collector.traces.size).to eq(1)
    end
  end

  describe '#traces_for_run' do
    let(:collector) { described_class.new }
    
    before do
      # Add traces from different optimization runs
      collector.collect_trace('llm.response', {
        'trace_id' => 'trace-1',
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'attributes' => {},
        'metadata' => { optimization_run_id: 'run-001' }
      })
      
      collector.collect_trace('llm.response', {
        'trace_id' => 'trace-2', 
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'attributes' => {},
        'metadata' => { optimization_run_id: 'run-002' }
      })
    end

    it 'filters traces by optimization run ID' do
      run_traces = collector.traces_for_run('run-001')
      
      expect(run_traces.size).to eq(1)
      expect(run_traces.first.trace_id).to eq('trace-1')
    end

    it 'returns empty array for unknown run ID' do
      expect(collector.traces_for_run('unknown')).to be_empty
    end
  end

  describe '#llm_traces' do
    let(:collector) { described_class.new }

    before do
      # Add LLM trace
      collector.collect_trace('llm.response', {
        'trace_id' => 'llm-trace',
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'attributes' => {},
        'metadata' => {}
      })

      # Add module trace
      collector.collect_trace('chain_of_thought.reasoning_complete', {
        'trace_id' => 'module-trace',
        'event_name' => 'chain_of_thought.reasoning_complete',
        'timestamp' => Time.now,
        'attributes' => {},
        'metadata' => {}
      })
    end

    it 'returns only LLM traces' do
      llm_traces = collector.llm_traces
      
      expect(llm_traces.size).to eq(1)
      expect(llm_traces.first.trace_id).to eq('llm-trace')
      expect(llm_traces.first.llm_trace?).to be(true)
    end
  end

  describe '#module_traces' do
    let(:collector) { described_class.new }

    before do
      # Add LLM trace
      collector.collect_trace('llm.response', {
        'trace_id' => 'llm-trace',
        'event_name' => 'llm.response', 
        'timestamp' => Time.now,
        'attributes' => {},
        'metadata' => {}
      })

      # Add module trace
      collector.collect_trace('chain_of_thought.reasoning_complete', {
        'trace_id' => 'module-trace',
        'event_name' => 'chain_of_thought.reasoning_complete',
        'timestamp' => Time.now,
        'attributes' => {},
        'metadata' => {}
      })
    end

    it 'returns only module traces' do
      module_traces = collector.module_traces
      
      expect(module_traces.size).to eq(1) 
      expect(module_traces.first.trace_id).to eq('module-trace')
      expect(module_traces.first.module_trace?).to be(true)
    end
  end

  describe '#clear' do
    let(:collector) { described_class.new }

    it 'clears all collected traces' do
      collector.collect_trace('llm.response', {
        'trace_id' => 'trace-1',
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'attributes' => {},
        'metadata' => {}
      })

      expect(collector.collected_count).to eq(1)
      
      collector.clear
      
      expect(collector.collected_count).to eq(0)
      expect(collector.traces).to be_empty
    end
  end

  describe 'thread safety' do
    let(:collector) { described_class.new }

    it 'handles concurrent trace collection safely' do
      threads = []
      
      10.times do |i|
        threads << Thread.new do
          collector.collect_trace('llm.response', {
            'trace_id' => "concurrent-trace-#{i}",
            'event_name' => 'llm.response',
            'timestamp' => Time.now,
            'attributes' => {},
            'metadata' => {}
          })
        end
      end
      
      threads.each(&:join)
      
      expect(collector.collected_count).to eq(10)
      trace_ids = collector.traces.map(&:trace_id)
      expect(trace_ids.uniq.size).to eq(10) # All unique
    end
  end
end