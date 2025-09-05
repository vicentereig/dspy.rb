# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe DSPy::Observability::AsyncSpanProcessor do
  let(:exporter) { instance_double(OpenTelemetry::Exporter::OTLP::Exporter) }
  
  before do
    allow(exporter).to receive(:shutdown)
    allow(exporter).to receive(:export).and_return(OpenTelemetry::SDK::Trace::Export::SUCCESS)
  end
  
  describe '#initialize' do
    it 'creates processor with default configuration' do
      processor = described_class.new(exporter, export_interval: 0) # Disable timer for tests
      
      expect(processor).to be_a(described_class)
      expect(processor).to respond_to(:on_start)
      expect(processor).to respond_to(:on_finish)
      expect(processor).to respond_to(:shutdown)
      expect(processor).to respond_to(:force_flush)
      
      processor.shutdown # Clean shutdown for test
    end

    it 'accepts custom configuration' do
      processor = described_class.new(
        exporter,
        queue_size: 500,
        export_interval: 0, # Disable timer for tests
        export_batch_size: 50,
        shutdown_timeout: 15
      )
      
      expect(processor).to be_a(described_class)
      processor.shutdown # Clean shutdown
    end
  end

  describe '#on_start' do
    it 'does not block when span starts' do
      processor = described_class.new(exporter, export_interval: 0)
      span = instance_double(OpenTelemetry::SDK::Trace::Span)
      parent_context = instance_double(OpenTelemetry::Context)
      
      start_time = Time.now
      processor.on_start(span, parent_context)
      elapsed = Time.now - start_time
      
      expect(elapsed).to be < 0.001 # Less than 1ms
      processor.shutdown
    end
  end

  describe '#on_finish' do
    it 'queues span without blocking' do
      processor = described_class.new(exporter, export_interval: 0)
      span = double('span')
      
      start_time = Time.now
      processor.on_finish(span)
      elapsed = Time.now - start_time
      
      expect(elapsed).to be < 0.001 # Less than 1ms
      processor.shutdown
    end

    it 'handles span queueing without errors' do
      processor = described_class.new(exporter, export_interval: 0)
      span = double('span')
      
      expect { processor.on_finish(span) }.not_to raise_error
      processor.shutdown
    end
  end

  describe '#shutdown' do
    it 'exports all queued spans before shutdown' do
      processor = described_class.new(exporter, export_interval: 0)
      spans = Array.new(3) { double('span') }
      
      # Queue some spans
      spans.each { |span| processor.on_finish(span) }
      
      # Should export all spans during shutdown
      expect(exporter).to receive(:export).with(spans, timeout: anything).and_return(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      expect(exporter).to receive(:shutdown)
      
      result = processor.shutdown
      expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
    end
  end

  describe '#force_flush' do
    it 'exports all queued spans immediately' do
      processor = described_class.new(exporter, export_interval: 0)
      spans = Array.new(2) { double('span') }
      
      spans.each { |span| processor.on_finish(span) }
      
      expect(exporter).to receive(:export).with(spans, timeout: anything).and_return(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      
      result = processor.force_flush
      expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      
      processor.shutdown
    end

    it 'returns success for empty queue' do
      processor = described_class.new(exporter, export_interval: 0)
      
      result = processor.force_flush
      expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      
      processor.shutdown
    end
  end

  describe 'async behavior' do
    it 'runs background task with timer when enabled' do
      processor = described_class.new(exporter, export_interval: 0.1) # Very short interval for test
      span = double('span')
      
      processor.on_finish(span)
      
      # Should eventually export via timer
      expect(exporter).to receive(:export).with([span], timeout: anything).and_return(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      
      sleep(0.15) # Wait for timer
      processor.shutdown
    end

    it 'exports immediately when batch size reached' do
      processor = described_class.new(exporter, export_batch_size: 2, export_interval: 0)
      spans = Array.new(2) { double('span') }
      
      # Should trigger immediate export
      expect(exporter).to receive(:export).with(spans, timeout: anything).and_return(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      
      spans.each { |span| processor.on_finish(span) }
      
      sleep(0.01) # Brief wait for async export
      processor.shutdown
    end
  end

  describe 'error handling' do
    it 'handles export errors gracefully' do
      processor = described_class.new(exporter, export_interval: 0)
      span = double('span')
      
      processor.on_finish(span)
      
      expect(exporter).to receive(:export).and_raise(StandardError.new("Test error"))
      expect(DSPy).to receive(:log).with('observability.export_error', anything)
      
      processor.force_flush
      processor.shutdown
    end
  end
end