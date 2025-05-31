require 'spec_helper'
require 'dspy/sorbet_chain_of_thought'
require 'dspy/sorbet_signature'

class MathProblem < DSPy::SorbetSignature
  description "Solve a math word problem"

  input do
    const :problem, String
  end

  output do
    const :answer, Float
    const :unit, T.nilable(String), default: nil
  end
end

RSpec.describe DSPy::SorbetChainOfThought do
  before do
    DSPy.configure do |config|
      config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  describe 'chain of thought reasoning' do
    let(:cot) { DSPy::SorbetChainOfThought.new(MathProblem) }

    it 'includes reasoning in the output' do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_chain_of_thought_math') do
        result = cot.call(problem: "If a train travels 60 miles per hour for 2.5 hours, how far does it travel?")
        
        expect(result).to respond_to(:reasoning)
        expect(result).to respond_to(:answer)
        expect(result).to respond_to(:unit)
        
        expect(result.reasoning).to be_a(String)
        expect(result.reasoning).not_to be_empty
        expect(result.reasoning.downcase).to match(/distance|speed|time|formula/)
        
        expect(result.answer).to be_a(Float)
        expect(result.answer).to eq(150.0)
        expect(result.unit).to eq("miles")
      end
    end

    it 'preserves original signature fields' do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_chain_of_thought_simple') do
        result = cot.call(problem: "What is 25 + 17?")
        
        expect(result.answer).to be_a(Float)
        expect(result.answer).to eq(42.0)
      end
    end
  end

  describe 'signature enhancement' do
    it 'adds reasoning field to output schema' do
      cot = DSPy::SorbetChainOfThought.new(MathProblem)
      
      # The enhanced signature should have all original fields plus reasoning
      output_schema = cot.instance_variable_get(:@signature_class).output_json_schema
      
      expect(output_schema[:properties]).to include(
        answer: { type: "number" },
        unit: { type: "string" },
        reasoning: { type: "string" }
      )
      
      expect(output_schema[:required]).to include("answer", "reasoning")
    end
  end
end
