require 'spec_helper'

class SentimentClassifier < DSPy::Signature
  description "Classify sentiment of a given sentence."

  input do
    required(:sentence).value(:string) #.description('The sentence whose sentiment you are analyzing')
  end
  output do
    required(:sentiment).value(included_in?: [:positive, :negative, :neutral])
    #.description('The allowed values to classify sentences')
    required(:confidence).value(:float) #.description('The confidence score for the classification')
  end
end

class SentimentClassifierWithDescriptions < DSPy::Signature
  description "Classify sentiment of a given sentence."

  input do
    required(:sentence)
      .value(:string)
      .meta(description: 'The sentence whose sentiment you are analyzing')
  end

  output do
    required(:sentiment)
      .value(included_in?: [:positive, :negative, :neutral])
      .meta(description: 'The allowed values to classify sentences')

    required(:confidence).value(:float)
                         .meta(description:'The confidence score for the classification')
  end
end

RSpec.describe DSPy::Predict do
  it 'defines input schema' do
    classifier = SentimentClassifier.new
    expect(classifier.class.input_schema.json_schema).to eq({ :$schema => "http://json-schema.org/draft-06/schema#",
                                                              :properties => { :sentence => { :type => "string" } },
                                                              :required => ["sentence"], :type => "object" })
  end

  it 'defines output schema' do
    classifier = SentimentClassifier.new
    expect(classifier.class.output_schema.json_schema).to eq({ :$schema => "http://json-schema.org/draft-06/schema#",
                                                               :properties => {:confidence=>{:type=>"number"}, :sentiment=>{:enum=>[:positive, :negative, :neutral]}},
                                                               :required => ["sentiment", "confidence"],
                                                               :type => "object" })
  end
end
