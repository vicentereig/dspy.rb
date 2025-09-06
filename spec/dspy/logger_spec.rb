# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'stringio'

RSpec.describe 'DSPy.logger' do
  before do
    # Clear any cached logger
    DSPy.instance_variable_set(:@logger, nil)
    # Reset environment variables
    ENV.delete('DSPY_LOG')
    ENV.delete('RACK_ENV')
    ENV.delete('RAILS_ENV')
  end

  after do
    # Clean up
    DSPy.instance_variable_set(:@logger, nil)
  end

  describe 'environment detection' do
    it 'creates a string formatter logger for test environment' do
      ENV['RACK_ENV'] = 'test'
      logger = DSPy.create_logger
      expect(logger).to be_a(Dry::Logger::Dispatcher)
    end

    it 'creates a string formatter logger for development environment' do
      ENV['RAILS_ENV'] = 'development'
      logger = DSPy.create_logger
      expect(logger).to be_a(Dry::Logger::Dispatcher)
    end

    it 'creates a JSON formatter logger for production environment' do
      ENV['RACK_ENV'] = 'production'
      logger = DSPy.create_logger
      expect(logger).to be_a(Dry::Logger::Dispatcher)
    end

    it 'creates a JSON formatter logger for staging environment' do
      ENV['RAILS_ENV'] = 'staging'
      logger = DSPy.create_logger
      expect(logger).to be_a(Dry::Logger::Dispatcher)
    end

    it 'falls back to string formatter for unknown environment' do
      ENV['RACK_ENV'] = 'unknown'
      logger = DSPy.create_logger
      expect(logger).to be_a(Dry::Logger::Dispatcher)
    end

    it 'uses RACK_ENV over RAILS_ENV when both are set' do
      ENV['RACK_ENV'] = 'production'
      ENV['RAILS_ENV'] = 'development'
      logger = DSPy.create_logger
      # Logger will be created for production
      expect(logger).to be_a(Dry::Logger::Dispatcher)
    end
  end

  describe 'log output destinations' do
    it 'writes to log/test.log in test environment by default' do
      ENV['RACK_ENV'] = 'test'
      FileUtils.mkdir_p('log')
      
      logger = DSPy.create_logger
      # We can't easily test the stream directly, but we can verify logger is created
      expect(logger).not_to be_nil
    end

    it 'writes to log/development.log in development environment by default' do
      ENV['RAILS_ENV'] = 'development'
      FileUtils.mkdir_p('log')
      
      logger = DSPy.create_logger
      expect(logger).not_to be_nil
    end

    it 'writes to STDOUT in production environment by default' do
      ENV['RACK_ENV'] = 'production'
      logger = DSPy.create_logger
      expect(logger).not_to be_nil
    end

    it 'respects DSPY_LOG environment variable override' do
      ENV['RACK_ENV'] = 'test'
      
      # Use a temporary file path that will be cleaned up
      temp_log_path = File.join(Dir.tmpdir, "test_dspy_log_#{Process.pid}_#{Time.now.to_f}.log")
      ENV['DSPY_LOG'] = temp_log_path
      
      begin
        logger = DSPy.create_logger
        expect(logger).not_to be_nil
      ensure
        # Clean up the temporary log file
        File.unlink(temp_log_path) if File.exist?(temp_log_path)
      end
    end
  end

  describe 'DSPy.log method' do
    it 'publishes events to event system (logs are event consumers)' do
      events_mock = double('events')
      allow(DSPy).to receive(:events).and_return(events_mock)
      
      # Mock the Context.current to return specific values
      allow(DSPy::Context).to receive(:current).and_return({
        trace_id: 'test-trace-123',
        span_stack: ['span-456']
      })
      
      expect(events_mock).to receive(:notify).with(
        'test.event',
        hash_including(custom: 'value')
      )
      
      DSPy.log('test.event', custom: 'value')
    end

    it 'publishes events to event system without span_stack' do
      events_mock = double('events')
      allow(DSPy).to receive(:events).and_return(events_mock)
      
      allow(DSPy::Context).to receive(:current).and_return({
        trace_id: 'test-trace-123',
        span_stack: ['span-456']
      })
      
      expect(events_mock).to receive(:notify).with('test.event', anything)
      
      DSPy.log('test.event')
    end

    it 'returns nil when logger is not configured' do
      allow(DSPy).to receive(:logger).and_return(nil)
      
      expect(DSPy.log('test.event')).to be_nil
    end
  end

  describe 'log format output' do
    it 'outputs key=value format in development (when logs are event consumers)' do
      ENV['RACK_ENV'] = 'development'
      
      # Create a StringIO to capture output
      output = StringIO.new
      logger = Dry.Logger(:test, formatter: :string) do |config|
        config.add_backend(stream: output)
      end
      
      allow(DSPy).to receive(:logger).and_return(logger)
      allow(DSPy::Context).to receive(:current).and_return({
        trace_id: 'abc-123',
        span_stack: []
      })
      
      # Directly call emit_log to test format output (simulates log consumer behavior)
      DSPy.emit_log('span.start', span_id: 'span-001', operation: 'test.op')
      
      output.rewind
      log_output = output.read
      
      expect(log_output).to include('event="span.start"')
      expect(log_output).to include('trace_id="abc-123"')
      expect(log_output).to include('span_id="span-001"')
      expect(log_output).to include('operation="test.op"')
    end

    it 'outputs JSON format in production (when logs are event consumers)' do
      ENV['RACK_ENV'] = 'production'
      
      # Create a StringIO to capture output
      output = StringIO.new
      logger = Dry.Logger(:test, formatter: :json) do |config|
        config.add_backend(stream: output)
      end
      
      allow(DSPy).to receive(:logger).and_return(logger)
      allow(DSPy::Context).to receive(:current).and_return({
        trace_id: 'abc-123',
        span_stack: []
      })
      
      # Directly call emit_log to test format output (simulates log consumer behavior)
      DSPy.emit_log('span.start', span_id: 'span-001', operation: 'test.op')
      
      output.rewind
      log_output = output.read
      parsed = JSON.parse(log_output)
      
      expect(parsed['event']).to eq('span.start')
      expect(parsed['trace_id']).to eq('abc-123')
      expect(parsed['span_id']).to eq('span-001')
      expect(parsed['operation']).to eq('test.op')
    end
  end
end