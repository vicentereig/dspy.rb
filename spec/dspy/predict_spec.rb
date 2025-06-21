require 'spec_helper'
require 'dspy/predict'
require 'dspy/signature'

class Classify < DSPy::Signature
  description "Classify sentiment of a given sentence."

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :sentence, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

class ValidatedSignature < DSPy::Signature
  description "Test signature with validation"

  input do
    const :required_field, String
    const :optional_field, T.nilable(String), default: nil
  end

  output do
    const :result, String
  end
end

class NumericSignature < DSPy::Signature
  description "Convert text to numeric values"

  input do
    const :text, String
  end

  output do
    const :integer_value, Integer
    const :float_value, Float
  end
end

RSpec.describe DSPy::Predict do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  describe 'sentiment classification example' do
    let(:classify) { DSPy::Predict.new(Classify) }
    
    it 'makes a prediction with the correct structure' do
      VCR.use_cassette('openai/gpt4o-mini/classify_sentiment') do
        prediction = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
        
        expect(prediction).to be_a(Classify.output_struct_class)
        expect([Classify::Sentiment::Positive, Classify::Sentiment::Negative, Classify::Sentiment::Neutral]).to include(prediction.sentiment)
        expect(prediction.confidence).to be_a(Float)
        expect(prediction.confidence).to be_between(0.0, 1.0)
      end
    end

    it 'returns a sentiment for the example' do
      VCR.use_cassette('openai/gpt4o-mini/classify_sentiment') do
        prediction = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
        expect(prediction.sentiment).to be_a(Classify::Sentiment)
      end
    end

    it 'provides reasonable confidence' do
      VCR.use_cassette('openai/gpt4o-mini/classify_sentiment') do
        prediction = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
        expect(prediction.confidence).to be > 0.5
      end
    end
  end

  describe 'input validation' do
    it 'raises error for missing required fields' do
      predictor = DSPy::Predict.new(ValidatedSignature)

      expect {
        predictor.call(optional_field: "test")  # missing required_field
      }.to raise_error(DSPy::PredictionInvalidError)
    end
  end

  describe 'type coercion' do
    it 'handles type coercion from LM output' do
      VCR.use_cassette('openai/gpt4o-mini/type_coercion') do
        predictor = DSPy::Predict.new(NumericSignature)
        result = predictor.call(text: "The number is forty-two point five")

        expect(result.integer_value).to be_a(Integer)
        expect(result.float_value).to be_a(Float)
      end
    end
  end
end
