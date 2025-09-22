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

# Union type test structures
class GeminiCreateAction < T::Struct
  const :name, String
  const :priority, String
  const :tags, T::Array[String]
end

class GeminiUpdateAction < T::Struct
  const :item_id, String
  const :changes, String
  const :reason, String
end

class GeminiDeleteAction < T::Struct
  const :item_id, String
  const :confirmation, T::Boolean
end

class GeminiUnionTypeSignature < DSPy::Signature
  description "Test signature with union types for action discrimination"
  
  input do
    const :command, String, description: "Action command to execute"
  end
  
  output do
    const :action, T.any(GeminiCreateAction, GeminiUpdateAction, GeminiDeleteAction), description: "Action to execute"
    const :success, T::Boolean, description: "Whether action is valid"
    const :message, String, description: "Status message"
  end
end

class GeminiOptionalFieldsSignature < DSPy::Signature
  description "Test signature with optional/nilable fields"
  
  input do
    const :query, String, description: "User query"
  end
  
  output do
    const :result, String, description: "Main result (required)"
    const :confidence, T.nilable(Float), description: "Optional confidence score"
    const :metadata, T.nilable(String), description: "Optional metadata string"
    const :category, T.nilable(String), description: "Optional category"
    const :error_code, T.nilable(Integer), description: "Optional error code"
  end
end

# Deeply nested structures for testing
class GeminiLevel4 < T::Struct
  const :value, String
  const :tags, T::Array[String]
end

class GeminiLevel3 < T::Struct
  const :name, String
  const :items, T::Array[GeminiLevel4]
  const :metadata, T::Hash[String, T.untyped]
end

class GeminiLevel2 < T::Struct
  const :category, String
  const :subcategories, T::Array[GeminiLevel3]
  const :count, Integer
end

class GeminiLevel1 < T::Struct
  const :section, String
  const :groups, T::Array[GeminiLevel2]
  const :total, Integer
  const :summary, String
end

class GeminiDeepNestingSignature < DSPy::Signature
  description "Test signature with deeply nested structures"
  
  input do
    const :topic, String, description: "Topic to structure"
  end
  
  output do
    const :structure, GeminiLevel1, description: "Deeply nested hierarchical structure"
    const :depth_level, Integer, description: "Maximum depth reached"
    const :complexity_score, Float, description: "Complexity rating"
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
    
    it "handles union types with proper discrimination" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      SSEVCR.use_cassette('gemini_structured_union') do
        lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        DSPy.configure { |config| config.lm = lm }
        
        predictor = DSPy::Predict.new(GeminiUnionTypeSignature)
        result = predictor.call(command: "Create a new task called 'Test Union Types' with high priority")
        
        # Should return one of the union types
        expect(result.action).to be_a(T::Struct)
        expect([GeminiCreateAction, GeminiUpdateAction, GeminiDeleteAction]).to include(result.action.class)
        
        # If it's a create action, verify the structure
        if result.action.is_a?(GeminiCreateAction)
          expect(result.action.name).to be_a(String)
          expect(result.action.priority).to be_a(String)
          expect(result.action.tags).to be_a(Array)
        end
        
        expect([true, false]).to include(result.success)
        expect(result.message).to be_a(String)
        expect(result.message).not_to be_empty
      end
    end
    
    it "handles optional/nilable fields correctly" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      SSEVCR.use_cassette('gemini_structured_optional') do
        lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        DSPy.configure { |config| config.lm = lm }
        
        predictor = DSPy::Predict.new(GeminiOptionalFieldsSignature)
        result = predictor.call(query: "Analyze this simple request")
        
        # Required field must be present
        expect(result.result).to be_a(String)
        expect(result.result).not_to be_empty
        
        # Optional fields can be nil or have values
        expect(result.confidence).to be_nil.or be_a(Float)
        expect(result.metadata).to be_nil.or be_a(String)
        expect(result.category).to be_nil.or be_a(String)
        expect(result.error_code).to be_nil.or be_a(Integer)
        
        # If confidence is present, it should be between 0 and 1
        if result.confidence
          expect(result.confidence).to be_between(0, 1)
        end
      end
    end
    
    it "handles deeply nested structures" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      SSEVCR.use_cassette('gemini_structured_nested') do
        lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        DSPy.configure { |config| config.lm = lm }
        
        predictor = DSPy::Predict.new(GeminiDeepNestingSignature)
        result = predictor.call(topic: "Programming languages categorization")
        
        # Verify top level structure
        expect(result.structure).to be_a(GeminiLevel1)
        expect(result.structure.section).to be_a(String)
        expect(result.structure.groups).to be_a(Array)
        expect(result.structure.total).to be_a(Integer)
        expect(result.structure.summary).to be_a(String)
        
        # Verify second level (if present)
        if result.structure.groups.any?
          group = result.structure.groups.first
          expect(group).to be_a(GeminiLevel2)
          expect(group.category).to be_a(String)
          expect(group.subcategories).to be_a(Array)
          expect(group.count).to be_a(Integer)
          
          # Verify third level (if present)
          if group.subcategories.any?
            subcat = group.subcategories.first
            expect(subcat).to be_a(GeminiLevel3)
            expect(subcat.name).to be_a(String)
            expect(subcat.items).to be_a(Array)
            expect(subcat.metadata).to be_a(Hash)
            
            # Verify fourth level (if present)
            if subcat.items.any?
              item = subcat.items.first
              expect(item).to be_a(GeminiLevel4)
              expect(item.value).to be_a(String)
              expect(item.tags).to be_a(Array)
              item.tags.each { |tag| expect(tag).to be_a(String) }
            end
          end
        end
        
        expect(result.depth_level).to be_a(Integer)
        expect(result.complexity_score).to be_a(Float)
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
    
    it "selects Gemini structured output strategy for Flash models (newly supported)" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      # Test with gemini-1.5-flash which now supports structured outputs
      lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
      selector = DSPy::LM::StrategySelector.new(lm.adapter, GeminiSentimentAnalysis)
      
      selected = selector.select
      expect(selected.name).to eq('gemini_structured_output')
      expect(selected).to be_available
    end
    
    it "falls back to enhanced prompting for unsupported models" do
      # Test with gemini-1.0-pro which doesn't support structured outputs
      lm = DSPy::LM.new('gemini/gemini-1.0-pro', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
      selector = DSPy::LM::StrategySelector.new(lm.adapter, GeminiSentimentAnalysis)
      
      selected = selector.select
      expect(selected.name).to eq('enhanced_prompting')
      expect(selected).to be_available
    end
  end
  
  describe "error handling and fallback behavior" do
    it "gracefully handles malformed schemas" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      # Create a signature that might cause issues
      malformed_signature = Class.new(DSPy::Signature) do
        description "Potentially problematic signature"
        
        input do
          const :query, String
        end
        
        output do
          const :result, String
          # This might cause issues with very deep nesting beyond Gemini limits
          const :deep_data, T::Hash[String, T::Hash[String, T::Hash[String, T::Hash[String, T::Hash[String, String]]]]]
        end
      end
      
      lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
      DSPy.configure { |config| config.lm = lm }
      
      predictor = DSPy::Predict.new(malformed_signature)
      
      # Test that malformed schemas are handled appropriately
      begin
        result = predictor.call(query: "Test deep nesting")
        # If it succeeds, verify basic structure
        expect(result.result).to be_a(String)
      rescue DSPy::LM::AdapterError => e
        # Expected behavior - Gemini rejects overly complex schemas
        expect(e.message).to include("Gemini adapter error")
      end
    end
    
    it "maintains fallback to enhanced prompting when structured outputs unavailable" do
      # Test with a legacy model that doesn't support structured outputs
      lm = DSPy::LM.new('gemini/gemini-1.0-pro', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
      selector = DSPy::LM::StrategySelector.new(lm.adapter, GeminiSentimentAnalysis)
      
      selected = selector.select
      expect(selected.name).to eq('enhanced_prompting')
      expect(selected).to be_available
    end
    
    it "handles API errors gracefully" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      # Test with invalid API key should fail gracefully
      lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: 'invalid-key', structured_outputs: true)
      predictor = DSPy::Predict.new(GeminiSentimentAnalysis)
      
      expect {
        predictor.call(text: "Test with invalid key")
      }.to raise_error(DSPy::LM::AdapterError)
    end
  end
end