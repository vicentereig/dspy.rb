require 'spec_helper'
require 'stringio'
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

class StructArraySignature < DSPy::Signature
  description "Process array of structured data"

  class Citation < T::Struct
    const :title, String
    const :author, String
    const :year, Integer
    const :relevance, Float
  end

  input do
    const :query, String
  end

  output do
    const :citations, T::Array[Citation]
    const :total_count, Integer
  end
end

RSpec.describe DSPy::Predict do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      # Preserve the logger configuration from spec_helper
      c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
    end
  end

  describe 'sentiment classification example' do
    let(:classify) { DSPy::Predict.new(Classify) }

    it 'makes a prediction with the correct structure' do
      VCR.use_cassette('openai/gpt4o-mini/classify_sentiment') do
        prediction = classify.call(sentence: "This book was super fun to read, though not the last chapter.")

        # Check that prediction responds to all expected output fields
        expect(prediction).to respond_to(:sentiment)
        expect(prediction).to respond_to(:confidence)
        # Check that prediction also includes input fields
        expect(prediction).to respond_to(:sentence)
        
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
    let(:text) { "The number is forty-two point five" }
    let(:predictor) { DSPy::Predict.new(NumericSignature) }
    let(:prediction) do
      VCR.use_cassette('openai/gpt4o-mini/type_coercion') do
        predictor.call(text: self.text)
      end
    end

    it 'includes the inputs in the prediction' do
      expect(prediction.text).to eq(self.text)
    end

    it 'coerces to integer' do
      expect(prediction.integer_value).to be_a(Integer)
    end

    it 'coerces to float' do
      expect(prediction.float_value).to be_a(Float)
    end
  end

  describe 'array of T::Struct coercion' do
    let(:query) { "Find papers about machine learning" }
    let(:predictor) { DSPy::Predict.new(StructArraySignature) }
    
    it 'properly coerces array of hashes to array of T::Struct objects' do
      VCR.use_cassette('openai/gpt4o-mini/struct_array_coercion') do
        prediction = predictor.call(query: query)
        
        # Check that citations is an array
        expect(prediction.citations).to be_a(Array)
        
        # Check that each citation is a proper Citation struct
        prediction.citations.each do |citation|
          expect(citation).to be_a(StructArraySignature::Citation)
          expect(citation.title).to be_a(String)
          expect(citation.author).to be_a(String)
          expect(citation.year).to be_a(Integer)
          expect(citation.relevance).to be_a(Float)
          expect(citation.relevance).to be_between(0.0, 1.0)
        end
        
        # Check total count
        expect(prediction.total_count).to be_a(Integer)
        expect(prediction.total_count).to eq(prediction.citations.length)
      end
    end
  end

end
