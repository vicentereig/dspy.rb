# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Module do
  let(:global_lm) { DSPy::LM.new('openai/gpt-3.5-turbo', api_key: 'global-key') }
  let(:instance_lm) { DSPy::LM.new('openai/gpt-4', api_key: 'instance-key') }

  # Test module that extends DSPy::Module
  let(:test_module_class) do
    Class.new(DSPy::Module) do
      def forward_untyped(**input_values)
        input_values
      end
    end
  end

  let(:test_module) { test_module_class.new }

  before do
    # Set global LM configuration
    DSPy.configure do |config|
      config.lm = global_lm
    end
  end

  describe '#lm' do
    let(:fiber_lm) { DSPy::LM.new('anthropic/claude-3', api_key: 'fiber-key') }

    after do
      # Clean up fiber-local context
      Fiber[:dspy_fiber_lm] = nil
    end

    it 'returns global LM when no instance LM is configured' do
      expect(test_module.lm).to eq(global_lm)
    end

    it 'returns instance LM when configured' do
      test_module.config.lm = instance_lm
      expect(test_module.lm).to eq(instance_lm)
    end

    it 'falls back to global LM when instance LM is nil' do
      test_module.config.lm = nil
      expect(test_module.lm).to eq(global_lm)
    end

    it 'returns fiber-local LM when no instance LM is configured' do
      DSPy.with_lm(fiber_lm) do
        expect(test_module.lm).to eq(fiber_lm)
      end
    end

    it 'prefers instance LM over fiber-local LM' do
      test_module.config.lm = instance_lm
      
      DSPy.with_lm(fiber_lm) do
        expect(test_module.lm).to eq(instance_lm)
      end
    end

    it 'falls back to fiber-local LM when instance LM is nil' do
      test_module.config.lm = nil
      
      DSPy.with_lm(fiber_lm) do
        expect(test_module.lm).to eq(fiber_lm)
      end
    end

    it 'hierarchy: instance > fiber-local > global' do
      # Only global
      expect(test_module.lm).to eq(global_lm)
      
      # Fiber-local overrides global
      DSPy.with_lm(fiber_lm) do
        expect(test_module.lm).to eq(fiber_lm)
        
        # Instance overrides fiber-local
        test_module.config.lm = instance_lm
        expect(test_module.lm).to eq(instance_lm)
      end
      
      # Back to instance (fiber-local context ended)
      expect(test_module.lm).to eq(instance_lm)
    end
  end

  describe '#configure' do
    it 'sets the instance LM using configure block' do
      test_module.configure do |config|
        config.lm = instance_lm
      end
      
      expect(test_module.lm).to eq(instance_lm)
    end

    it 'allows multiple configuration calls' do
      test_module.configure do |config|
        config.lm = instance_lm
      end
      
      expect(test_module.lm).to eq(instance_lm)
      
      test_module.configure do |config|
        config.lm = global_lm
      end
      
      expect(test_module.lm).to eq(global_lm)
    end
  end

  describe 'per-instance configuration' do
    it 'allows different modules to have different LMs' do
      module1 = test_module_class.new
      module2 = test_module_class.new
      
      module1.configure { |config| config.lm = instance_lm }
      # module2 uses default (global LM)
      
      expect(module1.lm).to eq(instance_lm)
      expect(module2.lm).to eq(global_lm)
    end

    it 'maintains separate configurations for different instances' do
      lm1 = DSPy::LM.new('openai/gpt-4-turbo', api_key: 'key1')
      lm2 = DSPy::LM.new('anthropic/claude-3', api_key: 'key2')
      
      module1 = test_module_class.new
      module2 = test_module_class.new
      
      module1.configure { |config| config.lm = lm1 }
      module2.configure { |config| config.lm = lm2 }
      
      expect(module1.lm).to eq(lm1)
      expect(module2.lm).to eq(lm2)
    end
  end

  describe 'configuration persistence' do
    it 'maintains instance configuration across method calls' do
      test_module.configure { |config| config.lm = instance_lm }
      
      # Call other methods
      test_module.forward(test: 'data')
      test_module.call(another: 'call')
      
      # Configuration should persist
      expect(test_module.lm).to eq(instance_lm)
    end
  end

  describe 'Dry::Configurable integration' do
    it 'provides access to config object' do
      expect(test_module.config).to respond_to(:lm)
      expect(test_module.config).to respond_to(:lm=)
    end

    it 'can be configured directly via config object' do
      test_module.config.lm = instance_lm
      expect(test_module.lm).to eq(instance_lm)
    end

    it 'supports finalization when configured' do
      expect {
        test_module.configure do |config|
          config.lm = instance_lm
        end
      }.not_to raise_error
    end
  end
end
