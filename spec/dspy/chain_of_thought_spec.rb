require 'spec_helper'

RSpec.describe DSPy::Signature do
  describe 'QA with chain of thought' do
    it 'answers the question' do
      VCR.use_cassette('openai/gpt4o-mini/qa_chain_of_thought') do
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
        DSPy.configure(lm: lm)
        
        class AnswerPredictor < DSPy::Signature
          description "Answers the question"
          
          input :question, String
          output :answer, String
        end
        
        qa = DSPy::ChainOfThought.new(AnswerPredictor)
        
        qa.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        
        expect(qa.answer).to eq("The probability that the sum equals two when two dice are tossed is 1/36.")
      end      
    end

  end
end 