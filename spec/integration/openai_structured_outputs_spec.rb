# frozen_string_literal: true

require 'spec_helper'

# Test signature for structured output testing
class SentimentType < T::Enum
  enums do
    Positive = new('positive')
    Negative = new('negative')
    Neutral = new('neutral')
  end
end

class SentimentAnalysis < DSPy::Signature
  description "Analyze the sentiment of a text"
  
  input do
    const :text, String, description: "Text to analyze"
  end
  
  output do
    const :sentiment, SentimentType, description: "Detected sentiment"
    const :confidence, Float, description: "Confidence score between 0 and 1"
    const :reasoning, String, description: "Explanation for the sentiment"
  end
end

class StructuredItem < T::Struct
  const :name, String
  const :value, Integer
  const :tags, T::Array[String]
end

class StructuredMetadata < T::Struct
  const :total_count, Integer
  const :processed_at, String
end

class ComplexOutput < DSPy::Signature
  description "Generate complex structured data"
  
  input do
    const :query, String, description: "User query"
  end
  
  output do
    const :items, T::Array[StructuredItem], description: "List of items"
    const :metadata, StructuredMetadata, description: "Processing metadata"
  end
end

RSpec.describe "OpenAI Structured Outputs Integration" do
  describe "with structured outputs enabled" do
    # No fallback key - tests will skip if ENV key is not available
    
    it "generates valid JSON with simple enum output", vcr: { cassette_name: "openai_structured_simple" } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'], structured_outputs: true)
      DSPy.configure { |config| config.lm = lm }
      
      predictor = DSPy::Predict.new(SentimentAnalysis)
      result = predictor.call(text: "I absolutely love this product! It exceeded all my expectations.")
      
      expect(result.sentiment).to be_a(SentimentType)
      expect(result.sentiment).to eq(SentimentType::Positive)
      expect(result.confidence).to be_a(Float)
      expect(result.confidence).to be_between(0, 1)
      expect(result.reasoning).to be_a(String)
      expect(result.reasoning).not_to be_empty
    end
    
    it "generates valid JSON with complex nested structures (OpenAI bug with nested arrays)", vcr: { cassette_name: "openai_structured_complex" } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'], structured_outputs: true)
      DSPy.configure { |config| config.lm = lm }
      
      predictor = DSPy::Predict.new(ComplexOutput)
      result = predictor.call(query: "List three popular programming languages with their usage")
      
      expect(result.items).to be_a(Array)
      expect(result.items).not_to be_empty
      
      result.items.each do |item|
        expect(item).to respond_to(:name)
        expect(item.name).to be_a(String)
        expect(item).to respond_to(:value)
        expect(item.value).to be_a(Integer)
        expect(item).to respond_to(:tags)
        expect(item.tags).to be_a(Array)
        item.tags.each { |tag| expect(tag).to be_a(String) }
      end
      
      expect(result.metadata).to respond_to(:total_count)
      expect(result.metadata.total_count).to be_a(Integer)
      expect(result.metadata).to respond_to(:processed_at)
      expect(result.metadata.processed_at).to be_a(String)
    end
    
    it "handles structured output responses correctly", vcr: { cassette_name: "openai_structured_simple_response" } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'], structured_outputs: true)
      DSPy.configure { |config| config.lm = lm }
      
      # Test that structured outputs work with a simple signature
      simple_test_class = Class.new(DSPy::Signature) do
        description "Generate a simple response"
        
        input do
          const :prompt, String, description: "Input prompt"
        end
        
        output do
          const :response, String, description: "Response"
          const :word_count, Integer, description: "Number of words in response"
        end
      end
      
      predictor = DSPy::Predict.new(simple_test_class)
      result = predictor.call(prompt: "Say hello in exactly three words")
      
      expect(result.response).to be_a(String)
      expect(result.word_count).to be_a(Integer)
      expect(result.word_count).to be > 0
    end
  end
  
  describe "with structured outputs disabled (backward compatibility)" do
    # No fallback key - tests will skip if ENV key is not available
    
    it "falls back to JSON parsing from response", vcr: { cassette_name: "openai_no_structured" } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'], structured_outputs: false)
      DSPy.configure { |config| config.lm = lm }
      
      predictor = DSPy::Predict.new(SentimentAnalysis)
      result = predictor.call(text: "This product is okay, nothing special.")
      
      # Should still work but using traditional JSON parsing
      expect(result.sentiment).to be_a(SentimentType)
      expect([SentimentType::Positive, SentimentType::Negative, SentimentType::Neutral]).to include(result.sentiment)
      expect(result.confidence).to be_a(Float)
      expect(result.reasoning).to be_a(String)
    end
  end
  
  describe "model capability detection" do
    it "enables structured outputs for supported models" do
      supported_models = [
        'openai/gpt-4o',
        'openai/gpt-4o-mini',
        'openai/gpt-4-turbo',
        'openai/gpt-4o-2024-08-06'
      ]
      
      supported_models.each do |model|
        expect(DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?(model)).to eq(true)
      end
    end
    
    it "disables structured outputs for unsupported models" do
      unsupported_models = [
        'openai/gpt-3.5-turbo',
        'openai/text-davinci-003',
        'openai/gpt-3.5-turbo-16k'
      ]
      
      unsupported_models.each do |model|
        expect(DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?(model)).to eq(false)
      end
    end
  end
  
  describe "edge cases" do
    
    # Test for mixed required/optional fields
    class MixedFieldsStruct < T::Struct
      const :required_field, String
      const :optional_field, T.nilable(String)
      const :required_number, Integer
      const :optional_array, T.nilable(T::Array[String])
    end
    
    class MixedFieldsOutput < DSPy::Signature
      description "Test mixed required and optional fields"
      
      input do
        const :query, String, description: "Query"
      end
      
      output do
        const :data, MixedFieldsStruct, description: "Mixed fields data"
      end
    end
    
    it "handles mixed required and optional (T.nilable) fields", vcr: { cassette_name: "openai_mixed_fields" } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'], structured_outputs: true)
      DSPy.configure { |config| config.lm = lm }
      
      predictor = DSPy::Predict.new(MixedFieldsOutput)
      result = predictor.call(query: "Generate data with some optional fields")
      
      expect(result.data.required_field).to be_a(String)
      expect(result.data.required_number).to be_a(Integer)
      # Optional fields can be nil or the specified type
      expect(result.data.optional_field).to be_nil.or be_a(String)
      expect(result.data.optional_array).to be_nil.or be_a(Array)
    end
    
  end
  
  describe "schema validation" do
    it "validates schema compatibility before sending" do
      # Create a schema with pattern properties (unsupported)
      problematic_signature = Class.new(DSPy::Signature) do
        output do
          const :data, T::Hash[String, String], description: "Dynamic keys"
        end
      end
      
      schema = problematic_signature.output_json_schema
      issues = DSPy::LM::Adapters::OpenAI::SchemaConverter.validate_compatibility(schema)
      
      # The hash type should work fine in our implementation
      expect(issues).to be_empty
    end
    
  end
end