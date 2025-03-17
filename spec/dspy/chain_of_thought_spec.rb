require 'spec_helper'

class AnswerPredictor < DSPy::Signature
  description "Provides a concise answer to the question"

  input do
    required(:question).value(:string)
  end
  output do
    required(:answer).value(:string)
  end
end

RSpec.describe DSPy::Signature do
  describe 'QA with chain of thought' do
    it 'answers the question' do
      VCR.use_cassette('openai/gpt4o-mini/qa_chain_of_thought_v2') do
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
        DSPy.configure(lm: lm)

        qa_cod = DSPy::ChainOfThought.new(AnswerPredictor)

        qa = qa_cod.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        expect(qa).to eq({
                           question: "Two dice are tossed. What is the probability that the sum equals two?",
                           answer: "1/36",
                           reasoning: "There is only one combination of the two dice that results in a sum of two, which is (1,1). Since there are a total of 36 possible outcomes when tossing two dice (6 sides on the first die times 6 sides on the second die), the probability is 1/36."
                         })
      end
    end


    it 'includes the reasoning' do
      VCR.use_cassette('openai/gpt4o-mini/qa_chain_of_thought_with_reasoning_v2') do
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
        DSPy.configure(lm: lm)

        qa_cod = DSPy::ChainOfThought.new(AnswerPredictor)

        qa = qa_cod.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        expect(qa[:reasoning]).to eq "When two dice are tossed, the only combination that results in a sum of two is (1,1). There are a total of 6 x 6 = 36 possible outcomes when rolling two dice. Therefore, the probability is 1 favorable outcome out of 36 possible outcomes, which simplifies to 1/36."
      end
    end
  end
end
