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
        
        qa_cod = DSPy::ChainOfThought.new(AnswerPredictor)
        
        qa = qa_cod.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        
        expect(qa.answer).to eq("1/36")
      end      
    end


    it 'includes the reasoning' do
      VCR.use_cassette('openai/gpt4o-mini/qa_chain_of_thought_with_reasoning') do
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
        DSPy.configure(lm: lm)
        
        class AnswerPredictor < DSPy::Signature
          description "Answers the question"
          
          input :question, String
          output :answer, String
        end
        
        qa_cod = DSPy::ChainOfThought.new(AnswerPredictor)
        
        qa = qa_cod.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
        expect(qa.reasoning).to eq "When two dice are tossed, the only combination that yields a sum of two is (1,1). Since there are a total of 6x6=36 possible outcomes when rolling two dice, the probability of getting a sum of two is 1 out of 36, which simplifies to 1/36."
      end      
    end
  end
end 