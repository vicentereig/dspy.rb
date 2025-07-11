# frozen_string_literal: true

require "spec_helper"

RSpec.describe DSPy::LM::CacheManager do
  let(:cache_manager) { described_class.new }
  
  # Mock signature class
  let(:signature_class) do
    Class.new(DSPy::Signature) do
      def self.name
        "TestSignature"
      end
      
      def self.output_json_schema
        {
          properties: {
            answer: { type: "string" },
            confidence: { type: "number" }
          },
          required: ["answer"]
        }
      end
    end
  end
  
  describe "#cache_schema and #get_schema" do
    it "caches and retrieves schemas" do
      schema = { type: "json_schema", json_schema: { name: "test" } }
      
      # Cache should be empty initially
      expect(cache_manager.get_schema(signature_class, "openai")).to be_nil
      
      # Cache the schema
      cache_manager.cache_schema(signature_class, "openai", schema)
      
      # Should retrieve the cached schema
      expect(cache_manager.get_schema(signature_class, "openai")).to eq(schema)
    end
    
    it "uses different cache keys for different providers" do
      schema1 = { type: "json_schema", json_schema: { name: "openai" } }
      schema2 = { type: "json_schema", json_schema: { name: "anthropic" } }
      
      cache_manager.cache_schema(signature_class, "openai", schema1)
      cache_manager.cache_schema(signature_class, "anthropic", schema2)
      
      expect(cache_manager.get_schema(signature_class, "openai")).to eq(schema1)
      expect(cache_manager.get_schema(signature_class, "anthropic")).to eq(schema2)
    end
    
    it "expires cached schemas after TTL" do
      schema = { type: "json_schema", json_schema: { name: "test" } }
      
      # Stub time to test expiration
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 1, 12, 0, 0))
      cache_manager.cache_schema(signature_class, "openai", schema)
      
      # Should retrieve before expiration
      expect(cache_manager.get_schema(signature_class, "openai")).to eq(schema)
      
      # Move time forward past TTL (1 hour + 1 second)
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 1, 13, 0, 1))
      
      # Should return nil after expiration
      expect(cache_manager.get_schema(signature_class, "openai")).to be_nil
    end
  end
  
  describe "#cache_capability and #get_capability" do
    it "caches and retrieves capability flags" do
      # Cache should be empty initially
      expect(cache_manager.get_capability("gpt-4o", "structured_outputs")).to be_nil
      
      # Cache the capability
      cache_manager.cache_capability("gpt-4o", "structured_outputs", true)
      
      # Should retrieve the cached capability
      expect(cache_manager.get_capability("gpt-4o", "structured_outputs")).to eq(true)
    end
    
    it "handles false values correctly" do
      cache_manager.cache_capability("gpt-3.5-turbo", "structured_outputs", false)
      expect(cache_manager.get_capability("gpt-3.5-turbo", "structured_outputs")).to eq(false)
    end
    
    it "uses longer TTL for capabilities" do
      # Capabilities have 24x longer TTL than schemas
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 1, 12, 0, 0))
      cache_manager.cache_capability("gpt-4o", "structured_outputs", true)
      
      # Should still be cached after 23 hours
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 2, 11, 0, 0))
      expect(cache_manager.get_capability("gpt-4o", "structured_outputs")).to eq(true)
      
      # Should expire after 24 hours + 1 second
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 2, 12, 0, 1))
      expect(cache_manager.get_capability("gpt-4o", "structured_outputs")).to be_nil
    end
  end
  
  describe "#clear!" do
    it "clears all caches" do
      cache_manager.cache_schema(signature_class, "openai", { test: "schema" })
      cache_manager.cache_capability("gpt-4o", "structured_outputs", true)
      
      expect(cache_manager.stats[:total_entries]).to eq(2)
      
      cache_manager.clear!
      
      expect(cache_manager.get_schema(signature_class, "openai")).to be_nil
      expect(cache_manager.get_capability("gpt-4o", "structured_outputs")).to be_nil
      expect(cache_manager.stats[:total_entries]).to eq(0)
    end
  end
  
  describe "#stats" do
    it "returns cache statistics" do
      stats = cache_manager.stats
      expect(stats).to eq({
        schema_entries: 0,
        capability_entries: 0,
        total_entries: 0
      })
      
      cache_manager.cache_schema(signature_class, "openai", { test: "schema" })
      cache_manager.cache_capability("gpt-4o", "structured_outputs", true)
      
      stats = cache_manager.stats
      expect(stats).to eq({
        schema_entries: 1,
        capability_entries: 1,
        total_entries: 2
      })
    end
  end
  
  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = []
      results = []
      mutex = Mutex.new
      
      # Create multiple threads that read and write concurrently
      10.times do |i|
        threads << Thread.new do
          # Write
          cache_manager.cache_capability("model-#{i}", "feature", i.even?)
          
          # Read
          result = cache_manager.get_capability("model-#{i}", "feature")
          mutex.synchronize { results << result }
        end
      end
      
      threads.each(&:join)
      
      # All operations should complete without errors
      expect(results.size).to eq(10)
      expect(results.select { |r| r == true }.size).to eq(5)  # Even indices
      expect(results.select { |r| r == false }.size).to eq(5) # Odd indices
    end
  end
  
  describe "DSPy::LM.cache_manager" do
    it "provides a global cache instance" do
      cache1 = DSPy::LM.cache_manager
      cache2 = DSPy::LM.cache_manager
      
      expect(cache1).to be_a(described_class)
      expect(cache1).to equal(cache2) # Same instance
    end
  end
end