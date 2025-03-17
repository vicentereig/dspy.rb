require 'spec_helper'

RSpec.describe DSPy::Predict do
  describe 'sentiment classification example' do
    before do
      VCR.use_cassette('openai/gpt4o-mini/classify_sentiment_v2') do
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
        DSPy.configure(lm: lm)

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

        # Run the prediction
        @prediction = @classify.call(sentence: "This book was super fun to read, though not the last chapter.")
      end
    end

    it 'makes a prediction with the correct structure' do
      expect(@prediction).to eq({:confidence=>0.85, :sentence=>"This book was super fun to read, though not the last chapter.", :sentiment=>"positive"})
    end

    it 'returns a mixed sentiment for the example' do
      expect(@prediction.sentiment).to eq('positive')
    end
  end
end
