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

    it 'has structured_outputs setting' do
      expect(DSPy.config).to respond_to(:structured_outputs)
      expect(DSPy.config.structured_outputs).to respond_to(:openai)
      expect(DSPy.config.structured_outputs).to respond_to(:anthropic)
    end

    it 'has test_mode setting' do
      expect(DSPy.config).to respond_to(:test_mode)
      expect(DSPy.config.test_mode).to eq(false)
    end

    it 'supports configuration blocks' do
      DSPy.configure do |config|
        config.test_mode = true
        config.structured_outputs.openai = true
      end

      expect(DSPy.config.test_mode).to eq(true)
      expect(DSPy.config.structured_outputs.openai).to eq(true)

      # Reset to defaults
      DSPy.configure do |config|
        config.test_mode = false
        config.structured_outputs.openai = false
      end
    end
  end
end 