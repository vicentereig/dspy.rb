# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Context do
  describe '.current' do
    it 'returns a thread-local context hash' do
      context = described_class.current
      expect(context).to be_a(Hash)
      expect(context).to have_key(:trace_id)
      expect(context).to have_key(:span_stack)
    end

    it 'generates a unique trace_id' do
      context = described_class.current
      expect(context[:trace_id]).to match(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
    end

    it 'initializes with an empty span stack' do
      context = described_class.current
      expect(context[:span_stack]).to eq([])
    end

    it 'returns the same context within the same thread' do
      context1 = described_class.current
      context2 = described_class.current
      expect(context1.object_id).to eq(context2.object_id)
    end

    it 'returns different contexts in different threads' do
      context1 = described_class.current
      context2 = nil
      
      thread = Thread.new do
        context2 = described_class.current
      end
      thread.join
      
      expect(context1[:trace_id]).not_to eq(context2[:trace_id])
    end
  end

  describe '.with_span' do
    before { described_class.clear! }

    it 'yields control to the block' do
      executed = false
      described_class.with_span(operation: 'test.operation') do
        executed = true
      end
      expect(executed).to be true
    end

    it 'returns the block result' do
      result = described_class.with_span(operation: 'test.operation') do
        'test_result'
      end
      expect(result).to eq('test_result')
    end

    it 'logs span start and end events' do
      expect(DSPy).to receive(:log).with('span.start', hash_including(
        trace_id: anything,
        span_id: anything,
        parent_span_id: nil,
        operation: 'test.operation'
      ))
      
      expect(DSPy).to receive(:log).with('span.end', hash_including(
        trace_id: anything,
        span_id: anything,
        duration_ms: anything
      ))
      
      described_class.with_span(operation: 'test.operation') { }
    end

    it 'tracks parent-child relationships' do
      parent_span_id = nil
      child_span_id = nil
      
      allow(DSPy).to receive(:log) do |event, attrs|
        if event == 'span.start'
          if attrs[:operation] == 'parent.operation'
            parent_span_id = attrs[:span_id]
          elsif attrs[:operation] == 'child.operation'
            child_span_id = attrs[:span_id]
            expect(attrs[:parent_span_id]).to eq(parent_span_id)
          end
        end
      end
      
      described_class.with_span(operation: 'parent.operation') do
        described_class.with_span(operation: 'child.operation') do
          # nested operation
        end
      end
    end

    it 'manages span stack correctly' do
      stack_during_parent = nil
      stack_during_child = nil
      
      described_class.with_span(operation: 'parent') do
        stack_during_parent = described_class.current[:span_stack].dup
        
        described_class.with_span(operation: 'child') do
          stack_during_child = described_class.current[:span_stack].dup
        end
      end
      
      expect(stack_during_parent.size).to eq(1)
      expect(stack_during_child.size).to eq(2)
      expect(described_class.current[:span_stack]).to be_empty
    end

    it 'calculates duration in milliseconds' do
      duration = nil
      
      allow(DSPy).to receive(:log) do |event, attrs|
        if event == 'span.end'
          duration = attrs[:duration_ms]
        end
      end
      
      described_class.with_span(operation: 'test') do
        sleep(0.01) # Sleep for 10ms
      end
      
      expect(duration).to be_between(10, 50)
    end

    it 'passes custom attributes to span start' do
      expect(DSPy).to receive(:log).with('span.start', hash_including(
        operation: 'test',
        custom_attr: 'value',
        another: 123
      ))
      
      allow(DSPy).to receive(:log).with('span.end', anything)
      
      described_class.with_span(operation: 'test', custom_attr: 'value', another: 123) { }
    end

    it 'handles exceptions and still logs span end' do
      expect(DSPy).to receive(:log).with('span.start', anything)
      expect(DSPy).to receive(:log).with('span.end', anything)
      
      expect do
        described_class.with_span(operation: 'failing') do
          raise 'test error'
        end
      end.to raise_error('test error')
    end
  end

  describe '.clear!' do
    it 'resets the thread-local context' do
      context1 = described_class.current
      trace_id1 = context1[:trace_id]
      
      described_class.clear!
      
      context2 = described_class.current
      trace_id2 = context2[:trace_id]
      
      expect(trace_id1).not_to eq(trace_id2)
    end
  end
end