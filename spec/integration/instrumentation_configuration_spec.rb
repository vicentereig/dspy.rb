# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Instrumentation Configuration Integration' do
  before do
    # Reset configuration before each test
    DSPy.config.instrumentation.enabled = false
    DSPy.config.instrumentation.subscribers = []
    DSPy.config.instrumentation.sampling_rate = 1.0
    DSPy.config.instrumentation.trace_level = :standard
  end

  it 'supports the documented configuration API from observability.md' do
    # This test demonstrates the exact API shown in the documentation
    DSPy.configure do |config|
      # Enable instrumentation
      config.instrumentation.enabled = true
      
      # Configure subscribers
      config.instrumentation.subscribers = [:logger]
      
      # Sampling configuration
      config.instrumentation.sampling_rate = 1.0
      config.instrumentation.trace_level = :detailed
    end

    # Configure nested logger settings
    DSPy.config.instrumentation.logger.level = :info
    DSPy.config.instrumentation.logger.include_payloads = true
    DSPy.config.instrumentation.logger.correlation_id = true

    # Verify configuration was applied
    expect(DSPy.config.instrumentation.enabled).to eq(true)
    expect(DSPy.config.instrumentation.subscribers).to eq([:logger])
    expect(DSPy.config.instrumentation.sampling_rate).to eq(1.0)
    expect(DSPy.config.instrumentation.trace_level).to eq(:detailed)
    
    expect(DSPy.config.instrumentation.logger.level).to eq(:info)
    expect(DSPy.config.instrumentation.logger.include_payloads).to eq(true)
    expect(DSPy.config.instrumentation.logger.correlation_id).to eq(true)

    # Validation should pass
    expect { DSPy.validate_instrumentation! }.not_to raise_error

    # Setup should work
    expect { DSPy::Instrumentation.setup_subscribers }.not_to raise_error
  end

  it 'supports production configuration pattern' do
    # Simulate production configuration from documentation
    DSPy.configure do |config|
      config.instrumentation.enabled = true
      
      # Production subscribers
      config.instrumentation.subscribers = [:logger]  # Using only logger for this test
      
      # Sampling for performance
      config.instrumentation.sampling_rate = 0.1  # 10% sampling in production
      config.instrumentation.trace_level = :standard
      
      # Performance settings
      config.instrumentation.async_processing = true
      config.instrumentation.buffer_size = 1000
      config.instrumentation.flush_interval = 30
      
      # Error handling
      config.instrumentation.error_reporting = true
      config.instrumentation.error_service = :sentry
    end

    # Verify production configuration
    config = DSPy.config.instrumentation
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
    expect { DSPy.validate_instrumentation! }.not_to raise_error

    # Setup should work
    expect { DSPy::Instrumentation.setup_subscribers }.not_to raise_error
  end

  it 'supports correlation ID configuration' do
    DSPy.config.instrumentation.correlation_id.enabled = true
    DSPy.config.instrumentation.correlation_id.header = 'X-Request-ID'
    DSPy.config.instrumentation.correlation_id.generator = -> { "custom-#{SecureRandom.hex(8)}" }

    config = DSPy.config.instrumentation.correlation_id
    expect(config.enabled).to eq(true)
    expect(config.header).to eq('X-Request-ID')
    
    # Test custom generator
    id = config.generator.call
    expect(id).to start_with('custom-')
    expect(id.length).to eq(23) # 'custom-' + 16 hex chars
  end

  it 'supports OpenTelemetry configuration' do
    DSPy.config.instrumentation.otel.tracer_name = 'my-dspy-app'
    DSPy.config.instrumentation.otel.service_name = 'my-service'
    DSPy.config.instrumentation.otel.service_version = '2.0.0'

    config = DSPy.config.instrumentation.otel
    expect(config.tracer_name).to eq('my-dspy-app')
    expect(config.service_name).to eq('my-service')
    expect(config.service_version).to eq('2.0.0')
  end

  it 'supports New Relic configuration' do
    DSPy.config.instrumentation.newrelic.app_name = 'My DSPy App'
    DSPy.config.instrumentation.newrelic.custom_attributes = {
      'dspy.version' => DSPy::VERSION,
      'deployment.environment' => 'test'
    }

    config = DSPy.config.instrumentation.newrelic
    expect(config.app_name).to eq('My DSPy App')
    expect(config.custom_attributes).to eq({
      'dspy.version' => DSPy::VERSION,
      'deployment.environment' => 'test'
    })
  end

  it 'supports Langfuse configuration' do
    DSPy.config.instrumentation.langfuse.track_tokens = false
    DSPy.config.instrumentation.langfuse.track_costs = false
    DSPy.config.instrumentation.langfuse.track_prompts = true

    config = DSPy.config.instrumentation.langfuse
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
      DSPy.config.instrumentation.enabled = true
      DSPy.config.instrumentation.subscribers = [:logger]

      expect { DSPy::Instrumentation.setup_subscribers }.not_to raise_error
    end
  end
end