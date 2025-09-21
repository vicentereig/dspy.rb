require 'spec_helper'
require 'stringio'

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
    let(:question) { "Two dice are tossed. What is the probability that the sum equals two?" }

    let(:prediction) do
      VCR.use_cassette('openai/gpt4o-mini/qa_chain_of_thought_v2') do
        qa_cod = DSPy::ChainOfThought.new(AnswerPredictor)
        qa_cod.call(question: question)
      end
    end

    it 'includes the reasoning' do
      expect(prediction.reasoning).to include("dice")
      expect(prediction.reasoning.length).to be > 50
    end

    it 'includes the answer' do
      expect(prediction.answer).to start_with "1/36"
    end

    it 'includes the question' do
      expect(prediction.question).to eq(question)
    end
  end

end
