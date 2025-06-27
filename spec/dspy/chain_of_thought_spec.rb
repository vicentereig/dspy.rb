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
      expect(prediction.reasoning).to start_with "When two dice are tossed"
    end

    it 'includes the answer' do
      expect(prediction.answer).to start_with "1/36"
    end

    it 'includes the question' do
      expect(prediction.question).to eq(question)
    end
  end

  describe 'logger subscriber integration' do
    let(:log_output) { StringIO.new }
    let(:test_logger) { Logger.new(log_output) }
    
    before do
      # Configure DSPy for testing
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
      
      # Create logger subscriber manually
      @logger_subscriber = DSPy::Subscribers::LoggerSubscriber.new(logger: test_logger)
    end

    after do
      # Clean up
      @logger_subscriber = nil
    end

    it 'logs chain of thought events when running actual predictions' do
      VCR.use_cassette('chain_of_thought_simple') do
        cot = DSPy::ChainOfThought.new(AnswerPredictor)
        result = cot.forward(question: "What is the capital of France?")

        log_content = log_output.string
        
        # Check that chain of thought, prediction, and LM events are logged in key-value format
        expect(log_content).to include("event=chain_of_thought signature=AnswerPredictor status=success")
        expect(log_content).to include("event=prediction") # Signature might be empty for internal predictions
        expect(log_content).to include("event=lm_request provider=openai model=gpt-4o-mini status=success")
      end
    end
  end
end
