require 'spec_helper'

class AnswerPredictor < DSPy::Signature
  description "Provides a concise answer to the question"

  input do
    const :question, String
  end
  output do
    const :answer, String
  end
end

RSpec.describe DSPy::Signature do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  describe 'QA with chain of thought' do
    it 'answers the question' do
      VCR.use_cassette('openai/gpt4o-mini/qa_chain_of_thought_v2') do
        qa_cod = DSPy::ChainOfThought.new(AnswerPredictor)

        qa = qa_cod.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        expect(qa.to_h.keys).to eq([:question, :answer, :reasoning])
      end
    end


    it 'includes the reasoning' do
      VCR.use_cassette('openai/gpt4o-mini/qa_chain_of_thought_with_reasoning_v2') do

        qa_cod = DSPy::ChainOfThought.new(AnswerPredictor)

        qa = qa_cod.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        expect(qa.reasoning).to start_with "There is only one way to get a sum"
      end
    end
  end
end
