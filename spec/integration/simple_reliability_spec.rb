# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Simple Reliability Features" do
  describe "Cache Manager" do
    it "caches OpenAI schema conversions" do
      cache_manager = DSPy::LM.cache_manager
      cache_manager.clear!
      
      # Define a test signature
      test_signature = Class.new(DSPy::Signature) do
        def self.name
          "CacheTestSignature"
        end
        
        description "Test signature for caching"
        
        output do
          const :result, String
        end
      end
      
      # First call should generate schema
      schema1 = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(test_signature)
      expect(cache_manager.stats[:schema_entries]).to eq(1)
      
      # Second call should use cache
      schema2 = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(test_signature)
      expect(schema1).to eq(schema2)
      
      # Verify cache was used by checking that only 1 entry exists
      expect(cache_manager.stats[:schema_entries]).to eq(1)
    end
    
    it "caches capability detection" do
      cache_manager = DSPy::LM.cache_manager
      cache_manager.clear!
      
      # First call
      result1 = DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?("openai/gpt-4o")
      expect(result1).to be true
      expect(cache_manager.stats[:capability_entries]).to eq(1)
      
      # Second call should use cache
      result2 = DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?("openai/gpt-4o")
      expect(result2).to be true
      expect(cache_manager.stats[:capability_entries]).to eq(1)
      
      # Different model should create new cache entry
      result3 = DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?("openai/gpt-3.5-turbo")
      expect(result3).to be false
      expect(cache_manager.stats[:capability_entries]).to eq(2)
    end
  end
  
  describe "Strategy Selection" do
    it "selects OpenAI structured output strategy when available" do
      # Create an adapter that supports structured outputs
      lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: "test-key", structured_outputs: true)
      
      # Create a test signature
      test_signature = Class.new(DSPy::Signature) do
        def self.name
          "StrategyTestSignature"
        end
        
        output do
          const :answer, String
        end
      end
      
      # Create strategy selector
      selector = DSPy::LM::StrategySelector.new(lm.adapter, test_signature)
      strategy = selector.select
      
      expect(strategy.name).to eq("openai_structured_output")
      expect(strategy.priority).to eq(100)
    end
    
    it "falls back to enhanced prompting for unsupported models" do
      # Create an adapter for a model without structured outputs
      lm = DSPy::LM.new("openai/gpt-3.5-turbo", api_key: "test-key")
      
      # Create a test signature
      test_signature = Class.new(DSPy::Signature) do
        def self.name
          "FallbackTestSignature"
        end
        
        output do
          const :answer, String
        end
      end
      
      # Create strategy selector
      selector = DSPy::LM::StrategySelector.new(lm.adapter, test_signature)
      strategy = selector.select
      
      expect(strategy.name).to eq("enhanced_prompting")
      expect(strategy.priority).to eq(50)
    end
    
    it "respects manual strategy override" do
      DSPy.configure do |config|
        config.structured_outputs.strategy = DSPy::Strategy::Compatible
      end
      
      # Even with a model that supports structured outputs
      lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: "test-key", structured_outputs: true)
      
      test_signature = Class.new(DSPy::Signature) do
        def self.name
          "OverrideTestSignature"
        end
        
        output do
          const :answer, String
        end
      end
      
      selector = DSPy::LM::StrategySelector.new(lm.adapter, test_signature)
      strategy = selector.select
      
      expect(strategy.name).to eq("enhanced_prompting")
      
      # Reset configuration
      DSPy.configure do |config|
        config.structured_outputs.strategy = nil
      end
    end
  end
  
  describe "Enhanced Prompting Strategy" do
    it "can extract JSON from various formats" do
      lm = DSPy::LM.new("openai/gpt-3.5-turbo", api_key: "test-key")
      
      test_signature = Class.new(DSPy::Signature) do
        def self.name
          "ExtractionTestSignature"
        end
        
        output do
          const :answer, String
        end
      end
      
      strategy = DSPy::LM::Strategies::EnhancedPromptingStrategy.new(lm.adapter, test_signature)
      
      # Test extraction from markdown code block
      response1 = DSPy::LM::Response.new(
        content: "Here's the answer:\n```json\n{\"answer\": \"42\"}\n```",
        metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test')
      )
      extracted1 = strategy.extract_json(response1)
      expect(extracted1).to eq('{"answer": "42"}')
      
      # Test extraction from plain JSON
      response2 = DSPy::LM::Response.new(
        content: '{"answer": "42"}',
        metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test')
      )
      extracted2 = strategy.extract_json(response2)
      expect(extracted2).to eq('{"answer": "42"}')
      
      # Test extraction from JSON with text
      response3 = DSPy::LM::Response.new(
        content: 'The result is: {"answer": "42"} as requested.',
        metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test')
      )
      extracted3 = strategy.extract_json(response3)
      expect(extracted3).to eq('{"answer": "42"}')
    end
  end
  
  describe "Retry Configuration" do
    before do
      # Reset to defaults before test
      DSPy.configure do |config|
        config.structured_outputs.retry_enabled = true
        config.structured_outputs.max_retries = 3
        config.structured_outputs.fallback_enabled = true
      end
    end
    
    after do
      # Reset to defaults after test
      DSPy.configure do |config|
        config.structured_outputs.retry_enabled = true
        config.structured_outputs.max_retries = 3
        config.structured_outputs.fallback_enabled = true
      end
    end
    
    it "respects retry configuration settings" do
      # Test default settings
      expect(DSPy.config.structured_outputs.retry_enabled).to be true
      expect(DSPy.config.structured_outputs.max_retries).to eq(3)
      expect(DSPy.config.structured_outputs.fallback_enabled).to be true
      
      # Test configuration changes
      DSPy.configure do |config|
        config.structured_outputs.retry_enabled = false
        config.structured_outputs.max_retries = 5
      end
      
      expect(DSPy.config.structured_outputs.retry_enabled).to be false
      expect(DSPy.config.structured_outputs.max_retries).to eq(5)
    end
  end
end