require 'spec_helper'

class QuestionAnswerer < DSPy::Signature
  description "Answer a question."
  
  input do
    const :question, String, description: "The question to answer"
  end
  
  output do
    const :answer, String, description: "The answer to the question"
  end
end

class Assess < DSPy::Signature
  description "Assess the quality of a tweet along the specified dimension."
  
  input do
    const :assessed_text, String, description: "The text to assess"
    const :assessment_question, String, description: "The assessment criteria question"
  end
  
  output do
    const :assessment_answer, T::Boolean, description: "Boolean assessment result"
  end
end

class Metric
  # Evaluates the engagement and correctness of a predicted answer.
  #
  # @param gold [Object] an object containing the expected question and answer.
  # @param pred [Object] an object containing the predicted answer.
  #
  # @return [Array<Boolean>] an array containing the engagement and correctness assessments.
  def self.call(gold:, pred:)
    engaging = DSPy::Predict.new(Assess)
    engagement = engaging.call(assessed_text: pred.answer, assessment_question: "Does the assessed text make for a self-contained, engaging tweet")

    correct = DSPy::Predict.new(Assess)
    correctness = correct.call(assessed_text: pred.answer, assessment_question: "The text should answer `#{gold.question}` with `#{gold.answer}`. Does the assessed text contain this answer")

    score = [engagement.assessment_answer, correctness.assessment_answer].select { |t| t == true && pred.answer.length <= 280}.length
    score / 2.0
  end
end

RSpec.describe 'Evals' do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  it 'evaluates correctness and engagement of a tweet' do
    VCR.use_cassette('openai/gpt4o-mini/evals') do
      program = DSPy::Predict.new(QuestionAnswerer)
      pred = program.call(question: "What is the capital of France?")
      example_class = Data.define(:question, :answer)
      gold = example_class.new(question: "What is the capital of France?", answer: "Paris")
      score = Metric.call(gold:, pred:)

      expect(score).to be >= 0.0
    end
  end
end
