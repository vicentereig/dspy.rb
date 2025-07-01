# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Nested Configuration Classes' do
  describe DSPy::Configuration::CorrelationIdConfig do
    before do
      # Reset configuration before each test
      described_class.configure do |config|
        config.enabled = false
        config.header = 'X-Correlation-ID'
        config.generator = -> { SecureRandom.uuid }
      end
    end

    it 'has correct default values' do
      config = described_class.config
      
      expect(config.enabled).to eq(false)
      expect(config.header).to eq('X-Correlation-ID')
      expect(config.generator).to be_a(Proc)
    end

    it 'allows configuration changes' do
      described_class.configure do |config|
        config.enabled = true
        config.header = 'X-Request-ID'
      end

      expect(described_class.config.enabled).to eq(true)
      expect(described_class.config.header).to eq('X-Request-ID')
    end

    it 'generator produces UUID-like strings' do
      id = described_class.config.generator.call
      expect(id).to be_a(String)
      expect(id.length).to eq(36) # Standard UUID length
    end
  end

  describe DSPy::Configuration::LoggerConfig do
    before do
      # Reset configuration before each test
      described_class.configure do |config|
        config.level = :info
        config.include_payloads = true
        config.correlation_id = true
        config.sampling = {}
        config.sampling_conditions = {}
      end
    end

    it 'has correct default values' do
      config = described_class.config
      
      expect(config.level).to eq(:info)
      expect(config.include_payloads).to eq(true)
      expect(config.correlation_id).to eq(true)
      expect(config.sampling).to eq({})
      expect(config.sampling_conditions).to eq({})
    end

    it 'allows configuration changes' do
      described_class.configure do |config|
        config.level = :debug
        config.include_payloads = false
        config.sampling = { prediction_events: 0.1 }
      end

      expect(described_class.config.level).to eq(:debug)
      expect(described_class.config.include_payloads).to eq(false)
      expect(described_class.config.sampling).to eq({ prediction_events: 0.1 })
    end
  end

  describe DSPy::Configuration::OtelConfig do
    before do
      # Reset configuration before each test
      described_class.configure do |config|
        config.tracer_name = 'dspy-ruby'
        config.service_name = 'dspy-application'
        config.service_version = DSPy::VERSION
        config.endpoint = -> { ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] }
      end
    end

    it 'has correct default values' do
      config = described_class.config
      
      expect(config.tracer_name).to eq('dspy-ruby')
      expect(config.service_name).to eq('dspy-application')
      expect(config.service_version).to eq(DSPy::VERSION)
      expect(config.endpoint).to be_a(Proc)
    end

    it 'allows configuration changes' do
      described_class.configure do |config|
        config.tracer_name = 'my-dspy-app'
        config.service_name = 'my-service'
      end

      expect(described_class.config.tracer_name).to eq('my-dspy-app')
      expect(described_class.config.service_name).to eq('my-service')
    end
  end

  describe DSPy::Configuration::NewRelicConfig do
    before do
      # Reset configuration before each test
      described_class.configure do |config|
        config.app_name = 'DSPy Application'
        config.license_key = -> { ENV['NEW_RELIC_LICENSE_KEY'] }
        config.custom_attributes = {}
      end
    end

    it 'has correct default values' do
      config = described_class.config
      
      expect(config.app_name).to eq('DSPy Application')
      expect(config.license_key).to be_a(Proc)
      expect(config.custom_attributes).to eq({})
    end

    it 'allows configuration changes' do
      described_class.configure do |config|
        config.app_name = 'My DSPy App'
        config.custom_attributes = { environment: 'production' }
      end

      expect(described_class.config.app_name).to eq('My DSPy App')
      expect(described_class.config.custom_attributes).to eq({ environment: 'production' })
    end
  end

  describe DSPy::Configuration::LangfuseConfig do
    before do
      # Reset configuration before each test
      described_class.configure do |config|
        config.public_key = -> { ENV['LANGFUSE_PUBLIC_KEY'] }
        config.secret_key = -> { ENV['LANGFUSE_SECRET_KEY'] }
        config.host = -> { ENV['LANGFUSE_HOST'] }
        config.track_tokens = true
        config.track_costs = true
        config.track_prompts = true
      end
    end

    it 'has correct default values' do
      config = described_class.config
      
      expect(config.public_key).to be_a(Proc)
      expect(config.secret_key).to be_a(Proc)
      expect(config.host).to be_a(Proc)
      expect(config.track_tokens).to eq(true)
      expect(config.track_costs).to eq(true)
      expect(config.track_prompts).to eq(true)
    end

    it 'allows configuration changes' do
      described_class.configure do |config|
        config.track_tokens = false
        config.track_costs = false
      end

      expect(described_class.config.track_tokens).to eq(false)
      expect(described_class.config.track_costs).to eq(false)
    end
  end
end