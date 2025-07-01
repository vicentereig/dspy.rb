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
      expect(DSPy.config.instrumentation).to respond_to(:enabled)
      expect(DSPy.config.instrumentation).to respond_to(:logger)
    end

    it 'supports clean configuration API' do
      # Direct property access
      DSPy.config.instrumentation.enabled = true
      DSPy.config.instrumentation.subscribers = [:logger]
      DSPy.config.instrumentation.logger.level = :debug

      expect(DSPy.config.instrumentation.enabled).to eq(true)
      expect(DSPy.config.instrumentation.subscribers).to eq([:logger])
      expect(DSPy.config.instrumentation.logger.level).to eq(:debug)

      # Configuration blocks work too
      DSPy.configure do |config|
        config.instrumentation.enabled = false
        config.instrumentation.logger.level = :info
      end

      expect(DSPy.config.instrumentation.enabled).to eq(false)
      expect(DSPy.config.instrumentation.logger.level).to eq(:info)

      # Validation should pass
      DSPy.config.instrumentation.enabled = true
      DSPy.config.instrumentation.subscribers = [:logger]
      expect { DSPy.validate_instrumentation! }.not_to raise_error

      # Reset to defaults
      DSPy.config.instrumentation.enabled = false
      DSPy.config.instrumentation.subscribers = []
      DSPy.config.instrumentation.logger.level = :info
    end
  end
end 