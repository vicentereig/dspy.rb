# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Configuration-Driven Instrumentation Setup' do
  let(:instrumentation_config) { DSPy.config.instrumentation }

  before do
    # Reset configuration before each test
    instrumentation_config.configure do |config|
      config.enabled = false
      config.subscribers = []
      config.sampling_rate = 1.0
      config.trace_level = :standard
      config.buffer_size = 1000
      config.flush_interval = 30
      config.error_reporting = false
      config.error_service = nil
    end
  end

  describe 'DSPy::Instrumentation.setup_subscribers' do
    context 'when instrumentation is disabled' do
      before do
        instrumentation_config.configure do |config|
          config.enabled = false
          config.subscribers = [:logger]
        end
      end

      it 'does not set up any subscribers' do
        # Mock the subscriber methods to verify they are not called
        expect(DSPy::Instrumentation).not_to receive(:setup_logger_subscriber)
        expect(DSPy::Instrumentation).not_to receive(:setup_otel_subscriber)
        
        DSPy::Instrumentation.setup_subscribers
      end
    end

    context 'when instrumentation is enabled' do
      before do
        instrumentation_config.configure do |config|
          config.enabled = true
        end
      end

      it 'validates configuration before setup' do
        instrumentation_config.configure do |config|
          config.enabled = true
          config.subscribers = [] # Invalid: enabled but no subscribers
        end

        expect { DSPy::Instrumentation.setup_subscribers }.to raise_error(ArgumentError, /Must specify at least one subscriber/)
      end

      it 'sets up logger subscriber when configured' do
        instrumentation_config.configure do |config|
          config.subscribers = [:logger]
        end

        expect(DSPy::Instrumentation).to receive(:setup_logger_subscriber)
        DSPy::Instrumentation.setup_subscribers
      end

      it 'sets up multiple subscribers when configured' do
        instrumentation_config.configure do |config|
          config.subscribers = [:logger, :otel]
        end

        # Mock dependency availability
        allow(DSPy::Instrumentation).to receive(:otel_available?).and_return(true)

        expect(DSPy::Instrumentation).to receive(:setup_logger_subscriber)
        expect(DSPy::Instrumentation).to receive(:setup_otel_subscriber)
        DSPy::Instrumentation.setup_subscribers
      end

      it 'validation catches unknown subscriber types' do
        instrumentation_config.configure do |config|
          config.subscribers = [:unknown]
        end

        expect { DSPy::Instrumentation.setup_subscribers }.to raise_error(ArgumentError, /Invalid subscribers: unknown/)
      end

      it 'skips subscribers when dependencies are not available' do
        instrumentation_config.configure do |config|
          config.subscribers = [:otel]
        end

        # Mock dependency check to return false
        allow(DSPy::Instrumentation).to receive(:otel_available?).and_return(false)
        expect(DSPy::Instrumentation).not_to receive(:setup_otel_subscriber)
        
        DSPy::Instrumentation.setup_subscribers
      end
    end
  end

  describe 'subscriber configuration setup' do
    before do
      instrumentation_config.configure do |config|
        config.enabled = true
        config.subscribers = [:logger]
      end
    end

    it 'creates logger subscriber when configured' do
      # Configure nested logger settings
      instrumentation_config.config.logger.configure do |logger_config|
        logger_config.level = :debug
        logger_config.include_payloads = false
        logger_config.correlation_id = false
      end

      expect(DSPy::Instrumentation).to receive(:logger_subscriber).and_call_original

      DSPy::Instrumentation.setup_subscribers
    end
  end

  describe 'dependency checking methods' do
    describe '.otel_available?' do
      it 'returns true when OpenTelemetry is available' do
        allow(DSPy::Instrumentation).to receive(:require).with('opentelemetry/sdk').and_return(true)
        expect(DSPy::Instrumentation.otel_available?).to eq(true)
      end

      it 'returns false when OpenTelemetry is not available' do
        allow(DSPy::Instrumentation).to receive(:require).with('opentelemetry/sdk').and_raise(LoadError)
        expect(DSPy::Instrumentation.otel_available?).to eq(false)
      end
    end

    describe '.newrelic_available?' do
      it 'returns true when New Relic is available' do
        allow(DSPy::Instrumentation).to receive(:require).with('newrelic_rpm').and_return(true)
        expect(DSPy::Instrumentation.newrelic_available?).to eq(true)
      end

      it 'returns false when New Relic is not available' do
        allow(DSPy::Instrumentation).to receive(:require).with('newrelic_rpm').and_raise(LoadError)
        expect(DSPy::Instrumentation.newrelic_available?).to eq(false)
      end
    end

    describe '.langfuse_available?' do
      it 'returns true when Langfuse is available' do
        allow(DSPy::Instrumentation).to receive(:require).with('langfuse').and_return(true)
        expect(DSPy::Instrumentation.langfuse_available?).to eq(true)
      end

      it 'returns false when Langfuse is not available' do
        allow(DSPy::Instrumentation).to receive(:require).with('langfuse').and_raise(LoadError)
        expect(DSPy::Instrumentation.langfuse_available?).to eq(false)
      end
    end
  end

  describe 'backward compatibility' do
    it 'preserves legacy setup_subscribers_legacy method' do
      expect(DSPy::Instrumentation).to respond_to(:setup_subscribers_legacy)
    end

    it 'legacy method still creates logger subscriber' do
      expect(DSPy::Instrumentation).to receive(:logger_subscriber).and_call_original
      DSPy::Instrumentation.setup_subscribers_legacy
    end
  end
end