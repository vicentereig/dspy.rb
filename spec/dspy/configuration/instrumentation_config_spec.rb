# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Configuration::InstrumentationConfig do
  describe 'default configuration' do
    it 'has correct default values' do
      config = described_class.config
      
      expect(config.enabled).to eq(false)
      expect(config.subscribers).to eq([])
      expect(config.sampling_rate).to eq(1.0)
      expect(config.trace_level).to eq(:standard)
      expect(config.async_processing).to eq(false)
      expect(config.buffer_size).to eq(1000)
      expect(config.flush_interval).to eq(30)
      expect(config.error_reporting).to eq(false)
      expect(config.error_service).to be_nil
    end
  end

  describe 'configuration' do
    it 'allows setting enabled flag' do
      described_class.configure do |config|
        config.enabled = true
      end
      
      expect(described_class.config.enabled).to eq(true)
    end

    it 'allows setting subscribers' do
      described_class.configure do |config|
        config.subscribers = [:logger, :otel]
      end
      
      expect(described_class.config.subscribers).to eq([:logger, :otel])
    end

    it 'allows setting sampling rate' do
      described_class.configure do |config|
        config.sampling_rate = 0.5
      end
      
      expect(described_class.config.sampling_rate).to eq(0.5)
    end

    it 'allows setting trace level' do
      described_class.configure do |config|
        config.trace_level = :detailed
      end
      
      expect(described_class.config.trace_level).to eq(:detailed)
    end

    it 'allows setting async processing' do
      described_class.configure do |config|
        config.async_processing = true
      end
      
      expect(described_class.config.async_processing).to eq(true)
    end

    it 'allows setting buffer size' do
      described_class.configure do |config|
        config.buffer_size = 2000
      end
      
      expect(described_class.config.buffer_size).to eq(2000)
    end

    it 'allows setting flush interval' do
      described_class.configure do |config|
        config.flush_interval = 60
      end
      
      expect(described_class.config.flush_interval).to eq(60)
    end

    it 'allows setting error reporting' do
      described_class.configure do |config|
        config.error_reporting = true
      end
      
      expect(described_class.config.error_reporting).to eq(true)
    end

    it 'allows setting error service' do
      described_class.configure do |config|
        config.error_service = :sentry
      end
      
      expect(described_class.config.error_service).to eq(:sentry)
    end
  end

  describe 'validation' do
    before do
      # Reset configuration before each test
      described_class.configure do |config|
        config.enabled = false
        config.subscribers = []
        config.sampling_rate = 1.0
        config.trace_level = :standard
        config.buffer_size = 1000
        config.flush_interval = 30
      end
    end

    it 'validates successfully with default configuration' do
      expect { described_class.validate! }.not_to raise_error
    end

    it 'validates successfully when disabled' do
      described_class.configure do |config|
        config.enabled = false
        config.subscribers = []
      end
      
      expect { described_class.validate! }.not_to raise_error
    end

    it 'validates successfully when enabled with valid subscribers' do
      described_class.configure do |config|
        config.enabled = true
        config.subscribers = [:logger]
      end
      
      expect { described_class.validate! }.not_to raise_error
    end

    it 'raises error when enabled without subscribers' do
      described_class.configure do |config|
        config.enabled = true
        config.subscribers = []
      end
      
      expect { described_class.validate! }.to raise_error(ArgumentError, /Must specify at least one subscriber/)
    end

    it 'raises error for invalid sampling rate (too low)' do
      described_class.configure do |config|
        config.sampling_rate = -0.1
      end
      
      expect { described_class.validate! }.to raise_error(ArgumentError, /Sampling rate must be between 0.0 and 1.0/)
    end

    it 'raises error for invalid sampling rate (too high)' do
      described_class.configure do |config|
        config.sampling_rate = 1.1
      end
      
      expect { described_class.validate! }.to raise_error(ArgumentError, /Sampling rate must be between 0.0 and 1.0/)
    end

    it 'raises error for invalid buffer size' do
      described_class.configure do |config|
        config.buffer_size = 0
      end
      
      expect { described_class.validate! }.to raise_error(ArgumentError, /Buffer size must be positive/)
    end

    it 'raises error for invalid flush interval' do
      described_class.configure do |config|
        config.flush_interval = 0
      end
      
      expect { described_class.validate! }.to raise_error(ArgumentError, /Flush interval must be positive/)
    end

    it 'raises error for invalid trace level' do
      described_class.configure do |config|
        config.trace_level = :invalid
      end
      
      expect { described_class.validate! }.to raise_error(ArgumentError, /Invalid trace level/)
    end

    it 'raises error for invalid subscribers' do
      described_class.configure do |config|
        config.subscribers = [:logger, :invalid_subscriber]
      end
      
      expect { described_class.validate! }.to raise_error(ArgumentError, /Invalid subscribers: invalid_subscriber/)
    end

    it 'allows valid trace levels' do
      [:minimal, :standard, :detailed].each do |level|
        described_class.configure do |config|
          config.trace_level = level
        end
        
        expect { described_class.validate! }.not_to raise_error
      end
    end

    it 'allows valid subscribers' do
      [:logger, :otel, :newrelic, :langfuse].each do |subscriber|
        described_class.configure do |config|
          config.enabled = true
          config.subscribers = [subscriber]
        end
        
        expect { described_class.validate! }.not_to raise_error
      end
    end

    it 'allows multiple valid subscribers' do
      described_class.configure do |config|
        config.enabled = true
        config.subscribers = [:logger, :otel, :newrelic, :langfuse]
      end
      
      expect { described_class.validate! }.not_to raise_error
    end

    it 'allows boundary values for sampling rate' do
      [0.0, 1.0].each do |rate|
        described_class.configure do |config|
          config.sampling_rate = rate
        end
        
        expect { described_class.validate! }.not_to raise_error
      end
    end
  end
end