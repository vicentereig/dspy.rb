require 'spec_helper'
require 'dspy/module'
require 'dspy/predict'
require 'dspy/re_act'
require 'dspy/chain_of_thought'
require 'dspy/teleprompt/utils'
require 'dspy/tools/base'
require 'dspy/example'
require 'dspy/few_shot_example'

class PredictorDiscoverySignature < DSPy::Signature
  description "Simple question answering signature for predictor discovery specs"

  input do
    const :question, String, description: "Question text"
  end

  output do
    const :answer, String, description: "Answer text"
  end
end

module PredictorDiscovery
  class EchoTool < DSPy::Tools::Base
    tool_name "echo"
    tool_description "Returns provided question"

    sig { params(question: String).returns(String) }
    def call(question:)
      "echo: #{question}"
    end
  end
end

RSpec.describe 'Predictor discovery parity' do
  describe DSPy::Predict do
    it 'returns self as sole predictor' do
      predict = DSPy::Predict.new(PredictorDiscoverySignature)

      names = predict.named_predictors.map(&:first)
      predictors = predict.predictors

      expect(names).to contain_exactly("self")
      expect(predictors).to contain_exactly(predict)
    end
  end

  describe DSPy::ReAct do
    it 'exposes thought and observation predictors' do
      react = DSPy::ReAct.new(PredictorDiscoverySignature, tools: [PredictorDiscovery::EchoTool.new], max_iterations: 1)

      names = react.named_predictors.map(&:first)
      predictors = react.predictors

      expect(names).to match_array(%w[thought_generator observation_processor])
      expect(predictors.map(&:class)).to all(eq(DSPy::Predict).or(eq(DSPy::ChainOfThought)))
      expect(predictors.size).to eq(2)
    end
  end

  describe DSPy::Teleprompt::Utils do
    it 'creates demo slots for every predictor the student exposes' do
      student = DSPy::ReAct.new(PredictorDiscoverySignature, tools: [PredictorDiscovery::EchoTool.new], max_iterations: 1)
      trainset = [
        DSPy::Example.new(
          signature_class: PredictorDiscoverySignature,
          input: { question: "What is DSPy?" },
          expected: { answer: "A declarative framework." },
          id: "ex1"
        )
      ]

      allow(DSPy::Teleprompt::Utils).to receive(:create_bootstrapped_demos).and_return([])

      demo_candidates = DSPy::Teleprompt::Utils.create_n_fewshot_demo_sets(
        student,
        3,
        trainset,
        include_non_bootstrapped: true
      )

      expect(demo_candidates.keys.size).to eq(2)
      expect(demo_candidates.keys).to match_array([0, 1])
    end
  end
end
