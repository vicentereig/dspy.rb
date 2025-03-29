require 'spec_helper'

RSpec.describe DSPy::Predict do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  describe 'sentiment classification example' do
    it 'raises an exception when sending wrong params' do
      VCR.use_cassette('openai/gpt4o-mini/predict_validation') do
        class Classify < DSPy::Signature
          description "Classify sentiment of a given sentence."

          input do
            required(:sentence).value(:string).meta(description: 'The sentence whose sentiment you are analyzing')
          end

          output do
            required(:sentiment).value(included_in?: %w(positive negative neutral))
                                .meta(description: 'The allowed values to classify sentences')
            required(:confidence).value(:float).meta(description: 'The confidence score for the classification')
          end
        end
        # Create the predictor
        @classify = DSPy::Predict.new(Classify)

        expect { @classify.call(sentence: 1337) }.to raise_error(DSPy::PredictionInvalidError)
      end
    end
  end
end
