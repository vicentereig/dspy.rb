# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Instrumentation Configuration Integration' do
  before do
    # Reset configuration before each test
    DSPy.config.instrumentation.configure do |config|
      config.enabled = false
      config.subscribers = []
      config.sampling_rate = 1.0
      config.trace_level = :standard
    end
  end

  it 'supports the documented configuration API from observability.md' do
    # This test demonstrates the exact API shown in the documentation
    DSPy.configure do |config|
      config.instrumentation.configure do |inst_config|
        # Enable instrumentation
        inst_config.enabled = true
        
        # Configure subscribers
        inst_config.subscribers = [:logger]
        
        # Sampling configuration
        inst_config.sampling_rate = 1.0
        inst_config.trace_level = :detailed
      end
    end

    # Configure nested logger settings
    DSPy.config.instrumentation.config.logger.configure do |logger_config|
      logger_config.level = :info
      logger_config.include_payloads = true
      logger_config.correlation_id = true
    end

    # Verify configuration was applied
    expect(DSPy.config.instrumentation.config.enabled).to eq(true)
    expect(DSPy.config.instrumentation.config.subscribers).to eq([:logger])
    expect(DSPy.config.instrumentation.config.sampling_rate).to eq(1.0)
    expect(DSPy.config.instrumentation.config.trace_level).to eq(:detailed)
    
    expect(DSPy.config.instrumentation.config.logger.config.level).to eq(:info)
    expect(DSPy.config.instrumentation.config.logger.config.include_payloads).to eq(true)
    expect(DSPy.config.instrumentation.config.logger.config.correlation_id).to eq(true)

    # Validation should pass
    expect { DSPy.config.instrumentation.validate! }.not_to raise_error

    # Setup should work
    expect { DSPy::Instrumentation.setup_subscribers }.not_to raise_error
  end

  it 'supports production configuration pattern' do
    # Simulate production configuration from documentation
    DSPy.configure do |config|
      config.instrumentation.configure do |inst_config|
        inst_config.enabled = true
        
        # Production subscribers
        inst_config.subscribers = [:logger]  # Using only logger for this test
        
        # Sampling for performance
        inst_config.sampling_rate = 0.1  # 10% sampling in production
        inst_config.trace_level = :standard
        
        # Performance settings
        inst_config.async_processing = true
        inst_config.buffer_size = 1000
        inst_config.flush_interval = 30
        
        # Error handling
        inst_config.error_reporting = true
        inst_config.error_service = :sentry
      end
    end

    # Verify production configuration
    config = DSPy.config.instrumentation.config
    expect(config.enabled).to eq(true)
    expect(config.subscribers).to eq([:logger])
    expect(config.sampling_rate).to eq(0.1)
    expect(config.trace_level).to eq(:standard)
    expect(config.async_processing).to eq(true)
    expect(config.buffer_size).to eq(1000)
    expect(config.flush_interval).to eq(30)
    expect(config.error_reporting).to eq(true)
    expect(config.error_service).to eq(:sentry)

    # Validation should pass
    expect { DSPy.config.instrumentation.validate! }.not_to raise_error

    # Setup should work
    expect { DSPy::Instrumentation.setup_subscribers }.not_to raise_error
  end

  it 'supports correlation ID configuration' do
    DSPy.config.instrumentation.config.correlation_id.configure do |corr_config|
      corr_config.enabled = true
      corr_config.header = 'X-Request-ID'
      corr_config.generator = -> { "custom-#{SecureRandom.hex(8)}" }
    end

    config = DSPy.config.instrumentation.config.correlation_id.config
    expect(config.enabled).to eq(true)
    expect(config.header).to eq('X-Request-ID')
    
    # Test custom generator
    id = config.generator.call
    expect(id).to start_with('custom-')
    expect(id.length).to eq(23) # 'custom-' + 16 hex chars
  end

  it 'supports OpenTelemetry configuration' do
    DSPy.config.instrumentation.config.otel.configure do |otel_config|
      otel_config.tracer_name = 'my-dspy-app'
      otel_config.service_name = 'my-service'
      otel_config.service_version = '2.0.0'
    end

    config = DSPy.config.instrumentation.config.otel.config
    expect(config.tracer_name).to eq('my-dspy-app')
    expect(config.service_name).to eq('my-service')
    expect(config.service_version).to eq('2.0.0')
  end

  it 'supports New Relic configuration' do
    DSPy.config.instrumentation.config.newrelic.configure do |nr_config|
      nr_config.app_name = 'My DSPy App'
      nr_config.custom_attributes = {
        'dspy.version' => DSPy::VERSION,
        'deployment.environment' => 'test'
      }
    end

    config = DSPy.config.instrumentation.config.newrelic.config
    expect(config.app_name).to eq('My DSPy App')
    expect(config.custom_attributes).to eq({
      'dspy.version' => DSPy::VERSION,
      'deployment.environment' => 'test'
    })
  end

  it 'supports Langfuse configuration' do
    DSPy.config.instrumentation.config.langfuse.configure do |langfuse_config|
      langfuse_config.track_tokens = false
      langfuse_config.track_costs = false
      langfuse_config.track_prompts = true
    end

    config = DSPy.config.instrumentation.config.langfuse.config
    expect(config.track_tokens).to eq(false)
    expect(config.track_costs).to eq(false)
    expect(config.track_prompts).to eq(true)
  end

  describe 'backward compatibility' do
    it 'preserves existing manual setup approach' do
      # The old manual approach should still work
      expect { DSPy::Instrumentation.setup_subscribers_legacy }.not_to raise_error
      expect { DSPy::Instrumentation.logger_subscriber }.not_to raise_error
    end

    it 'allows mixing manual and configuration approaches' do
      # Manual subscriber creation should still work
      subscriber = DSPy::Instrumentation.logger_subscriber
      expect(subscriber).to be_a(DSPy::Subscribers::LoggerSubscriber)

      # Configuration approach should also work
      DSPy.config.instrumentation.configure do |config|
        config.enabled = true
        config.subscribers = [:logger]
      end

      expect { DSPy::Instrumentation.setup_subscribers }.not_to raise_error
    end
  end
end