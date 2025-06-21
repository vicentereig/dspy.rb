require 'spec_helper'

# Define sentiment enum for validation
class ValidationSentimentType < T::Enum
  enums do
    Positive = new("positive")
    Negative = new("negative") 
    Neutral = new("neutral")
  end
end

class ValidationClassify < DSPy::Signature
  description "Classify sentiment of a given sentence."

  input do
    const :sentence, String, description: "The sentence whose sentiment you are analyzing"
  end

  output do
    const :sentiment, ValidationSentimentType, description: "The sentiment classification (positive, negative, or neutral)"
    const :confidence, Float, description: "The confidence score for the classification"
  end
end

RSpec.describe DSPy::Predict do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  describe 'sentiment classification example' do
    it 'raises an exception when sending wrong params' do
      VCR.use_cassette('openai/gpt4o-mini/predict_validation') do
        # Create the predictor
        @classify = DSPy::Predict.new(ValidationClassify)

        # Test with wrong type - passing integer instead of string
        expect { @classify.call(sentence: 1337) }.to raise_error(TypeError)
      end
    end
  end
end
