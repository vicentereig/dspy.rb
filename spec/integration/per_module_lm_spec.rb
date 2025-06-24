# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Per-Module LM Configuration' do
  # Simple signature for testing
  class TestSignature < DSPy::Signature
    description "Test signature for per-module LM configuration"

    input do
      const :question, String, description: "A test question"
    end

    output do
      const :answer, String, description: "A test answer"
    end
  end

  let(:global_lm) { DSPy::LM.new('openai/gpt-3.5-turbo', api_key: 'global-key') }
  let(:instance_lm) { DSPy::LM.new('openai/gpt-4', api_key: 'instance-key') }

  before do
    # Set global LM configuration
    DSPy.configure do |config|
      config.lm = global_lm
    end
  end

  describe 'DSPy::Predict with per-instance LM' do
    it 'uses global LM by default' do
      predictor = DSPy::Predict.new(TestSignature)
      expect(predictor.lm).to eq(global_lm)
    end

    it 'uses instance LM when configured' do
      predictor = DSPy::Predict.new(TestSignature)
      predictor.configure { |config| config.lm = instance_lm }
      expect(predictor.lm).to eq(instance_lm)
    end

    it 'allows different predictors to use different LMs' do
      predictor1 = DSPy::Predict.new(TestSignature)
      predictor2 = DSPy::Predict.new(TestSignature)
      predictor2.configure { |config| config.lm = instance_lm }

      expect(predictor1.lm).to eq(global_lm)
      expect(predictor2.lm).to eq(instance_lm)
    end
  end

  describe 'DSPy::ChainOfThought with per-instance LM' do
    it 'inherits LM configuration from parent class' do
      cot = DSPy::ChainOfThought.new(TestSignature)
      expect(cot.lm).to eq(global_lm)

      cot_with_custom = DSPy::ChainOfThought.new(TestSignature)
      cot_with_custom.configure { |config| config.lm = instance_lm }
      expect(cot_with_custom.lm).to eq(instance_lm)
    end
  end

  describe 'DSPy::ReAct with per-instance LM' do
    let(:calculator_tool) do
      Class.new(DSPy::Tools::Base) do
        tool_name "calculator"
        tool_description "Simple calculator"

        sig { params(operation: String, x: Float, y: Float).returns(Float) }
        def call(operation:, x:, y:)
          case operation
          when "add" then x + y
          when "subtract" then x - y
          when "multiply" then x * y
          when "divide" then x / y
          else 0.0
          end
        end
      end.new
    end

    it 'inherits LM configuration from parent class' do
      react = DSPy::ReAct.new(TestSignature, tools: [calculator_tool])
      expect(react.lm).to eq(global_lm)

      react_with_custom = DSPy::ReAct.new(TestSignature, tools: [calculator_tool])
      react_with_custom.configure { |config| config.lm = instance_lm }
      expect(react_with_custom.lm).to eq(instance_lm)
    end
  end

  describe 'configure block patterns' do
    it 'supports standard configure block syntax' do
      predictor = DSPy::Predict.new(TestSignature)
      
      predictor.configure do |config|
        config.lm = instance_lm
      end

      expect(predictor.lm).to eq(instance_lm)
    end

    it 'supports direct config assignment' do
      predictor = DSPy::Predict.new(TestSignature)
      predictor.config.lm = instance_lm

      expect(predictor.lm).to eq(instance_lm)
    end

    it 'maintains configuration after method calls' do
      predictor = DSPy::Predict.new(TestSignature)
      predictor.configure { |config| config.lm = instance_lm }
      
      # Configuration should persist
      expect(predictor.lm).to eq(instance_lm)
      
      # Even after accessing other methods
      predictor.system_signature
      expect(predictor.lm).to eq(instance_lm)
    end
  end

  describe 'configuration isolation' do
    it 'does not affect global configuration' do
      predictor = DSPy::Predict.new(TestSignature)
      predictor.configure { |config| config.lm = instance_lm }
      
      # Global configuration should remain unchanged
      expect(DSPy.config.lm).to eq(global_lm)
    end

    it 'does not affect other instances' do
      predictor1 = DSPy::Predict.new(TestSignature)
      predictor2 = DSPy::Predict.new(TestSignature)
      predictor3 = DSPy::Predict.new(TestSignature)
      
      predictor2.configure { |config| config.lm = instance_lm }

      expect(predictor1.lm).to eq(global_lm)
      expect(predictor2.lm).to eq(instance_lm)
      expect(predictor3.lm).to eq(global_lm)
    end
  end

  describe 'multiple settings support' do
    it 'prepares for future configuration options' do
      predictor = DSPy::Predict.new(TestSignature)
      
      predictor.configure do |config|
        config.lm = instance_lm
        # Future settings could be added here:
        # config.temperature = 0.7
        # config.max_tokens = 1000
      end

      expect(predictor.lm).to eq(instance_lm)
    end
  end
end
