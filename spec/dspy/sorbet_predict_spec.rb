require 'spec_helper'
require 'dspy/sorbet_predict'
require 'dspy/sorbet_signature'

class SorbetClassify < DSPy::SorbetSignature
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

class ValidatedSignature < DSPy::SorbetSignature
  description "Test signature with validation"

  input do
    const :required_field, String
    const :optional_field, T.nilable(String), default: nil
  end

  output do
    const :result, String
  end
end

class NumericSignature < DSPy::SorbetSignature
  description "Convert text to numeric values"

  input do
    const :text, String
  end

  output do
    const :integer_value, Integer
    const :float_value, Float
  end
end

RSpec.describe DSPy::SorbetPredict do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  describe 'sentiment classification example' do
    let(:classify) { DSPy::SorbetPredict.new(SorbetClassify) }
    
    it 'makes a prediction with the correct structure' do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_classify_sentiment') do
        prediction = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
        
        expect(prediction).to be_a(SorbetClassify.output_struct_class)
        expect([SorbetClassify::Sentiment::Positive, SorbetClassify::Sentiment::Negative, SorbetClassify::Sentiment::Neutral]).to include(prediction.sentiment)
        expect(prediction.confidence).to be_a(Float)
        expect(prediction.confidence).to be_between(0.0, 1.0)
      end
    end

    it 'returns a sentiment for the example' do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_classify_sentiment') do
        prediction = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
        expect(prediction.sentiment).to be_a(SorbetClassify::Sentiment)
      end
    end

    it 'provides reasonable confidence' do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_classify_sentiment') do
        prediction = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
        expect(prediction.confidence).to be > 0.5
      end
    end
  end

  describe 'input validation' do
    it 'raises error for missing required fields' do
      predictor = DSPy::SorbetPredict.new(ValidatedSignature)

      expect {
        predictor.call(optional_field: "test")  # missing required_field
      }.to raise_error(DSPy::PredictionInvalidError)
    end
  end

  describe 'type coercion' do
    it 'handles type coercion from LM output' do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_type_coercion') do
        predictor = DSPy::SorbetPredict.new(NumericSignature)
        result = predictor.call(text: "The number is forty-two point five")

        expect(result.integer_value).to be_a(Integer)
        expect(result.float_value).to be_a(Float)
      end
    end
  end
end
