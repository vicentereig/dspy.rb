# frozen_string_literal: true

require 'spec_helper'

# Test signature for structured output testing
class GeminiSentimentType < T::Enum
  enums do
    Positive = new('positive')
    Negative = new('negative')
    Neutral = new('neutral')
  end
end

class GeminiSentimentAnalysis < DSPy::Signature
  description "Analyze the sentiment of a text"
  
  input do
    const :text, String, description: "Text to analyze"
  end
  
  output do
    const :sentiment, GeminiSentimentType, description: "Detected sentiment"
    const :confidence, Float, description: "Confidence score between 0 and 1"
    const :reasoning, String, description: "Explanation for the sentiment"
  end
end

class GeminiStructuredItem < T::Struct
  const :name, String
  const :value, Integer
  const :tags, T::Array[String]
end

class GeminiStructuredMetadata < T::Struct
  const :total_count, Integer
  const :processed_at, String
end

class GeminiComplexOutput < DSPy::Signature
  description "Generate complex structured data"
  
  input do
    const :query, String, description: "User query"
  end
  
  output do
    const :items, T::Array[GeminiStructuredItem], description: "List of items"
    const :metadata, GeminiStructuredMetadata, description: "Processing metadata"
  end
end

RSpec.describe "Gemini Structured Outputs Integration" do
  describe "with structured outputs enabled" do
    it "generates valid JSON with simple enum output" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      SSEVCR.use_cassette('gemini_structured_simple') do
        lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        DSPy.configure { |config| config.lm = lm }
        
        predictor = DSPy::Predict.new(GeminiSentimentAnalysis)
        result = predictor.call(text: "I absolutely love this product! It exceeded all my expectations.")
        
        expect(result.sentiment).to be_a(GeminiSentimentType)
        expect(result.sentiment).to eq(GeminiSentimentType::Positive)
        expect(result.confidence).to be_a(Float)
        expect(result.confidence).to be_between(0, 1)
        expect(result.reasoning).to be_a(String)
        expect(result.reasoning).not_to be_empty
      end
    end
    
    it "generates valid JSON with complex nested structures" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      SSEVCR.use_cassette('gemini_structured_complex') do
        lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        DSPy.configure { |config| config.lm = lm }
        
        predictor = DSPy::Predict.new(GeminiComplexOutput)
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
    end
  end

  describe "strategy selection" do
    it "selects Gemini structured output strategy for supported models" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      # Use gemini-1.5-pro which actually supports structured outputs
      lm = DSPy::LM.new('gemini/gemini-1.5-pro', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
      selector = DSPy::LM::StrategySelector.new(lm.adapter, GeminiSentimentAnalysis)
      
      selected = selector.select
      expect(selected.name).to eq('gemini_structured_output')
      expect(selected).to be_available
    end
    
    it "falls back to enhanced prompting for unsupported models" do
      # Test with gemini-1.5-flash which is JSON-only, not full schema support
      lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
      selector = DSPy::LM::StrategySelector.new(lm.adapter, GeminiSentimentAnalysis)
      
      selected = selector.select
      expect(selected.name).to eq('enhanced_prompting')
      expect(selected).to be_available
    end
  end
end