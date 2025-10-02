require 'spec_helper'
require 'dspy/signature'

# Define Sentiment as a T::Enum
class Sentiment < T::Enum
  enums do
    Positive = new('positive')
    Negative = new('negative')
    Neutral = new('neutral')
  end
end

class SentimentClassifier < DSPy::Signature
  description "Classify sentiment of a given sentence."

  input do
    const :sentence, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

class SentimentClassifierWithDefaults < DSPy::Signature
  description "Classify sentiment of a given sentence with optional fields."

  input do
    const :sentence, String
    const :context, T.nilable(String), default: nil
  end

  output do
    const :sentiment, String  # We'll use String and validate against enum values
    const :confidence, Float
    const :explanation, T.nilable(String), default: nil
  end
end

RSpec.describe DSPy::Signature do
  describe 'basic signature definition' do
    it 'defines input schema' do
      expect(SentimentClassifier.input_json_schema).to eq({
        "$schema": "http://json-schema.org/draft-06/schema#",
        type: "object",
        properties: { sentence: { type: "string" } },
        required: ["sentence"]
      })
    end

    it 'defines output schema' do
      expect(SentimentClassifier.output_json_schema).to eq({
        "$schema": "http://json-schema.org/draft-06/schema#",
        type: "object",
        properties: {
          sentiment: { type: "string", enum: %w[positive negative neutral] },
          confidence: { type: "number" }
        },
        required: %w[sentiment confidence]
      })
    end

    it 'stores description' do
      expect(SentimentClassifier.description).to eq("Classify sentiment of a given sentence.")
    end
  end

  describe 'signature with optional fields' do
    it 'handles optional fields in input schema' do
      expect(SentimentClassifierWithDefaults.input_json_schema).to eq({
        "$schema": "http://json-schema.org/draft-06/schema#",
        type: "object",
        properties: {
          sentence: { type: "string" },
          context: { type: ["string", "null"] }  # T.nilable(String) correctly generates nilable type
        },
        required: ["sentence"]  # context is not required due to default
      })
    end

    it 'handles optional fields in output schema' do
      expect(SentimentClassifierWithDefaults.output_json_schema).to eq({
        "$schema": "http://json-schema.org/draft-06/schema#",
        type: "object",
        properties: {
          sentiment: { type: "string" },  # For now, just string type
          confidence: { type: "number" },
          explanation: { type: ["string", "null"] }  # T.nilable(String) correctly generates nilable type
        },
        required: ["sentiment", "confidence"]  # explanation is not required due to default
      })
    end
  end

  describe 'struct instantiation' do
    it 'can create input struct instances' do
      input_data = { sentence: "This is great!" }
      input_struct = SentimentClassifier.input_struct_class.new(**input_data)

      expect(input_struct.sentence).to eq("This is great!")
    end

    it 'can create output struct instances' do
      output_data = {
        sentiment: Sentiment::Positive,
        confidence: 0.95
      }
      output_struct = SentimentClassifier.output_struct_class.new(**output_data)

      expect(output_struct.sentiment).to eq(Sentiment::Positive)
      expect(output_struct.confidence).to eq(0.95)
    end
  end

  describe 'enum handling' do
    it 'includes enum values in JSON schema' do
      class SentimentEnum < T::Enum
        enums do
          Positive = new('positive')
          Negative = new('negative')
          Neutral = new('neutral')
        end
      end

      class EnumSignature < DSPy::Signature
        description "Test enum handling"

        output do
          const :sentiment, SentimentEnum
          const :confidence, Float
        end
      end

      schema = EnumSignature.output_json_schema

      expect(schema[:properties][:sentiment]).to eq({
        type: "string",
        enum: ["positive", "negative", "neutral"]
      })

      expect(schema[:properties][:confidence]).to eq({
        type: "number"
      })
    end
  end
end
