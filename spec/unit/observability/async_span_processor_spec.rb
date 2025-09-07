# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Observability::AsyncSpanProcessor do
  let(:mock_exporter) { double('exporter') }
  let(:processor) { described_class.new(mock_exporter, export_interval: 0) } # Disable timer for tests
  
  describe '#export_spans_with_retry_async' do
    it 'logs the number of spans being exported' do
      spans = [double('span1'), double('span2'), double('span3')]
      span_data = [double('span_data1'), double('span_data2'), double('span_data3')]
      
      # Mock span to_span_data conversion
      spans.each_with_index { |span, i| allow(span).to receive(:to_span_data).and_return(span_data[i]) }
      
      # Mock successful export
      allow(mock_exporter).to receive(:export).and_return(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      
      # Expect diagnostic logging
      expect(DSPy).to receive(:log).with(
        'observability.export_attempt',
        spans_count: 3,
        batch_size: 3
      )
      
      expect(DSPy).to receive(:log).with(
        'observability.export_success',
        spans_count: 3,
        export_result: 'SUCCESS'
      )
      
      processor.send(:export_spans_with_retry_async, spans)
    end
    
    it 'logs export failures with retry attempts' do
      spans = [double('span1')]
      span_data = [double('span_data1')]
      
      allow(spans[0]).to receive(:to_span_data).and_return(span_data[0])
      
      # Mock failure then success
      allow(mock_exporter).to receive(:export).and_return(
        OpenTelemetry::SDK::Trace::Export::FAILURE,
        OpenTelemetry::SDK::Trace::Export::SUCCESS
      )
      
      # Expect initial attempt
      expect(DSPy).to receive(:log).with(
        'observability.export_attempt',
        spans_count: 1,
        batch_size: 1
      ).once
      
      # Expect retry logging 
      expect(DSPy).to receive(:log).with(
        'observability.export_retry',
        attempt: 1,
        spans_count: 1,
        backoff_seconds: 0.2
      )
      
      expect(DSPy).to receive(:log).with(
        'observability.export_success',
        spans_count: 1,
        export_result: 'SUCCESS'
      )
      
      # Mock async sleep
      allow(Async::Task).to receive_message_chain(:current, :sleep)
      
      processor.send(:export_spans_with_retry_async, spans)
    end
  end
  
  describe '#on_finish' do
    let(:mock_span) do
      double('span', context: double('context', trace_flags: double('flags', sampled?: true)))
    end
    
    it 'logs span queuing activity' do
      expect(DSPy).to receive(:log).with(
        'observability.span_queued',
        queue_size: 1
      )
      
      processor.on_finish(mock_span)
    end
    
    it 'logs when queue is full and spans are dropped' do
      small_processor = described_class.new(mock_exporter, queue_size: 2, export_interval: 0) 
      
      # Fill queue to capacity
      small_processor.on_finish(mock_span)
      small_processor.on_finish(mock_span)
      
      # This should trigger dropping
      expect(DSPy).to receive(:log).with(
        'observability.span_dropped',
        reason: 'queue_full',
        queue_size: 2
      )
      
      expect(DSPy).to receive(:log).with(
        'observability.span_queued',
        queue_size: 2
      )
      
      small_processor.on_finish(mock_span)
    end
  end
end