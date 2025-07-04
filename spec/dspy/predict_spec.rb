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

    it 'logs prediction events when running actual predictions' do
      VCR.use_cassette('predict_simple') do
        predictor = DSPy::Predict.new(Classify)
        result = predictor.forward(sentence: "I love this movie!")

        log_content = log_output.string
        
        # Check that both LM request and prediction events are logged in key-value format
        expect(log_content).to include("event=lm_request")
        expect(log_content).to include("provider=openai")
        expect(log_content).to include("model=gpt-4o-mini")
        expect(log_content).to include("status=success")
        expect(log_content).to include("event=prediction")
        expect(log_content).to include("signature=Classify")
      end
    end
  end
end
