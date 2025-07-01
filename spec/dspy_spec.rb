require 'spec_helper'

RSpec.describe DSPy do
  describe 'initial setup' do
    it 'has a working test environment' do
      expect(true).to be true
    end

    it 'defines the DSPy module' do
      expect(defined?(DSPy)).to eq('constant')
    end
  end

  describe 'configuration' do
    it 'has lm setting' do
      expect(DSPy.config).to respond_to(:lm)
    end

    it 'has logger setting' do
      expect(DSPy.config).to respond_to(:logger)
      expect(DSPy.config.logger).to be_a(Dry::Logger::Dispatcher)
    end

    it 'has instrumentation setting' do
      expect(DSPy.config).to respond_to(:instrumentation)
      expect(DSPy.config.instrumentation).to eq(DSPy::Configuration::InstrumentationConfig)
    end

    it 'allows configuring instrumentation settings' do
      # Test the configuration API works
      DSPy.config.instrumentation.configure do |inst_config|
        inst_config.enabled = true
        inst_config.subscribers = [:logger]
      end

      expect(DSPy.config.instrumentation.config.enabled).to eq(true)
      expect(DSPy.config.instrumentation.config.subscribers).to eq([:logger])

      # Validation should pass
      expect { DSPy.config.instrumentation.validate! }.not_to raise_error

      # Reset to defaults
      DSPy.config.instrumentation.configure do |inst_config|
        inst_config.enabled = false
        inst_config.subscribers = []
      end
    end
  end
end 