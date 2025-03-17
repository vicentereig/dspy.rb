require 'spec_helper'

ChainOfThoughtSchema = Dry::Schema.JSON do
  required(:reasoning).value(:string)
end

ClassifierSchema = Dry::Schema.JSON do
  required(:sentiment).value(included_in?: [:positive, :negative, :neutral])
  optional(:confidence).value(:float)
end

ClassifierWithReasoningSchema = Dry::Schema.JSON(parent: [ClassifierSchema, ChainOfThoughtSchema])

ChainOfThoughtSchemaWithDescription = Dry::Schema.JSON do
  required(:reasoning).value(:string).meta(description: 'Detailed reasoning behind the classification')
  optional(:confidence).value(:float).meta(description: 'Confidence score for the reasoning')
end

RSpec.describe 'Adding descriptions to JSON Schema fields' do
  it 'composes schemas' do
    result = ClassifierWithReasoningSchema.call({
      sentiment: :positive,
      confidence: 0.95})

    expect(result).to be_failure
  end

  it 'composes schemas and validations output' do
    result = ClassifierWithReasoningSchema.call({
      sentiment: :positive,
      confidence: 0.95,
      reasoning: "I am so stoked." })

    expect(result).to be_success
  end


  it 'supports dumping JSON Schema' do
    expected_json_schema = {:$schema => "http://json-schema.org/draft-06/schema#",
                            :properties => {
                              :confidence => {:type => "number"},
                              :sentiment => {:enum => [:positive, :negative, :neutral]}},
                            :required => ["sentiment"], :type => "object"
    }

    result = ClassifierSchema.json_schema
    expect(result).to include(expected_json_schema)
  end

  it 'supports adding description to JSON Schema' do
    expected_json_schema = {
      "$schema": "http://json-schema.org/draft-06/schema#",
      type: "object",
      properties: {
        reasoning: {
          type: "string",
          description: "Detailed reasoning behind the classification"
        },
        confidence: {
          type: "number",
          description: "Confidence score for the reasoning"
        }
      },
      required: ["reasoning"]
    }

    result = ChainOfThoughtSchemaWithDescription.json_schema
    expect(result).to include(expected_json_schema)
  end
end
