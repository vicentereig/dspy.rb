require 'spec_helper'
require 'dspy/code_act'
require 'dspy/predict'

RSpec.describe DSPy::CodeAct do
  describe '#named_predictors' do
    it 'exposes code and observation predictors' do
      signature_class = Class.new(DSPy::Signature) do
        input {}
        output {}
      end

      code_act = DSPy::CodeAct.new(signature_class, max_iterations: 1)

      names = code_act.named_predictors.map(&:first)
      predictors = code_act.predictors

      expect(names).to match_array(%w[code_generator observation_processor])
      expect(predictors.map(&:class)).to all(eq(DSPy::Predict))
    end
  end
end
