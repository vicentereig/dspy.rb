require 'spec_helper'
require 'dspy/teleprompt/mipro_v2'

RSpec.describe DSPy::Teleprompt::MIPROv2, 'dry-configurable integration' do
  # Reset class-level configuration before each test to prevent state pollution
  before do
    DSPy::Teleprompt::MIPROv2.instance_variable_set(:@default_config_block, nil)
  end
  describe 'class-level configuration' do
    it 'supports configure block for default settings' do
      # This test should pass now
      expect {
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.optimization_strategy = :bayesian
          config.num_trials = 30
          config.bootstrap_sets = 10
        end
      }.not_to raise_error

      # Test that configuration is applied to new instances
      optimizer = DSPy::Teleprompt::MIPROv2.new
      expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
      expect(optimizer.config.num_trials).to eq(30)
      expect(optimizer.config.bootstrap_sets).to eq(10)
    end

    it 'supports symbol-based optimization strategies' do
      expect {
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.optimization_strategy = :greedy
        end
      }.not_to raise_error
      
      expect {
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.optimization_strategy = :adaptive
        end
      }.not_to raise_error
      
      expect {
        DSPy::Teleprompt::MIPROv2.configure do |config|
          config.optimization_strategy = :bayesian
        end
      }.not_to raise_error
    end

    it 'rejects invalid optimization strategies when creating instance' do
      DSPy::Teleprompt::MIPROv2.configure do |config|
        config.optimization_strategy = :invalid_strategy
      end
      
      expect {
        DSPy::Teleprompt::MIPROv2.new
      }.to raise_error(ArgumentError, /Invalid optimization strategy/)
    end
  end

  describe 'instance-level configuration' do
    
    it 'supports configure block on instances' do
      optimizer = DSPy::Teleprompt::MIPROv2.new
      
      expect {
        optimizer.configure do |config|
          config.optimization_strategy = :adaptive
          config.num_trials = 15
          config.bootstrap_sets = 5
        end
      }.not_to raise_error

      expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Adaptive)
      expect(optimizer.config.num_trials).to eq(15)
      expect(optimizer.config.bootstrap_sets).to eq(5)
    end

    it 'overrides class-level configuration' do
      # Set class defaults
      DSPy::Teleprompt::MIPROv2.configure do |config|
        config.num_trials = 30
        config.optimization_strategy = :bayesian
      end

      # Instance should override
      optimizer = DSPy::Teleprompt::MIPROv2.new
      optimizer.configure do |config|
        config.num_trials = 10
        config.optimization_strategy = :greedy
      end

      expect(optimizer.config.num_trials).to eq(10)
      expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Greedy)
    end
  end

  describe 'AutoMode with new configuration' do
    it 'creates pre-configured instances without old config classes' do
      light_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.light
      expect(light_optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Greedy)
      expect(light_optimizer.config.num_trials).to eq(6)

      medium_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium  
      expect(medium_optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Adaptive)
      expect(medium_optimizer.config.num_trials).to eq(12)

      heavy_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.heavy
      expect(heavy_optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
      expect(heavy_optimizer.config.num_trials).to eq(18)
    end
  end

  describe 'new constructor without config parameter' do
    it 'creates optimizer without config parameter' do
      simple_metric = proc { |example, prediction| true }
      expect {
        DSPy::Teleprompt::MIPROv2.new(metric: simple_metric)
      }.not_to raise_error
    end

    it 'rejects old config parameter pattern' do
      # This should fail since we're removing backwards compatibility
      simple_metric = proc { |example, prediction| true }
      expect {
        DSPy::Teleprompt::MIPROv2.new(metric: simple_metric, config: "any_value")
      }.to raise_error(ArgumentError, /config parameter is no longer supported/)
    end
  end

  describe 'T::Enum integration' do
    it 'converts optimization_strategy to T::Enum internally' do
      optimizer = DSPy::Teleprompt::MIPROv2.new
      optimizer.configure do |config|
        config.optimization_strategy = :bayesian
      end

      # Internal usage should work with T::Enum comparison
      expect(optimizer.config.optimization_strategy).to be_a(DSPy::Teleprompt::OptimizationStrategy)
      expect(optimizer.config.optimization_strategy).to eq(DSPy::Teleprompt::OptimizationStrategy::Bayesian)
    end
  end
end