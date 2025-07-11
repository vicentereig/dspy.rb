# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Reliability Features Integration" do
  # Define a test signature
  class ReliabilityTestSignature < DSPy::Signature
    def self.name
      "ReliabilityTestSignature"
    end
    
    description "Test signature for reliability features"
    
    input do
      const :question, String, description: "The question to answer"
    end
    
    output do
      const :answer, String, description: "The answer to the question"
      const :confidence, Float, description: "Confidence score between 0 and 1"
    end
  end
  
  # Mock module that uses the signature
  class ReliabilityTestModule < DSPy::Module
    def initialize(signature_class: ReliabilityTestSignature)
      super()
      @predict = DSPy::ChainOfThought.new(signature_class)
    end
    
    def forward(question)
      @predict.forward(question: question)
    end
  end
  
  describe "retry with progressive fallback" do
    let(:module_instance) { ReliabilityTestModule.new }
    let(:lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: "test-key", structured_outputs: true) }
    
    before do
      module_instance.configure { |config| config.lm = lm }
      
      # Enable retry and set global LM fallback
      DSPy.configure do |config|
        config.lm = lm # Set global LM as fallback
        config.structured_outputs.retry_enabled = true
        config.structured_outputs.max_retries = 3
        config.test_mode = true # Disable sleep in tests
      end
    end
    
    it "succeeds on first try with valid JSON", vcr: { cassette_name: "reliability/success_first_try" } do
      # Mock the adapter to return valid JSON
      allow(lm.adapter).to receive(:chat).and_return(
        DSPy::LM::Response.new(
          content: '{"answer": "4", "confidence": 0.95}',
          usage: { prompt_tokens: 10, completion_tokens: 5 },
          metadata: {}
        )
      )
      
      result = module_instance.forward("What is 2+2?")
      
      expect(result.answer).to eq("4")
      expect(result.confidence).to eq(0.95)
    end
    
    it "retries and succeeds on second attempt", vcr: { cassette_name: "reliability/retry_success" } do
      call_count = 0
      
      allow(lm.adapter).to receive(:chat) do
        call_count += 1
        if call_count == 1
          # First attempt returns invalid JSON
          DSPy::LM::Response.new(
            content: "The answer is 4 with high confidence",
            usage: { prompt_tokens: 10, completion_tokens: 8 },
            metadata: {}
          )
        else
          # Second attempt returns valid JSON
          DSPy::LM::Response.new(
            content: '{"answer": "4", "confidence": 0.95}',
            usage: { prompt_tokens: 15, completion_tokens: 5 },
            metadata: {}
          )
        end
      end
      
      result = module_instance.forward("What is 2+2?")
      
      expect(result.answer).to eq("4")
      expect(result.confidence).to eq(0.95)
      expect(call_count).to eq(2)
    end
    
    it "falls back to enhanced prompting strategy", vcr: { cassette_name: "reliability/fallback_strategy" } do
      # Configure to use a model without structured outputs
      lm_fallback = DSPy::LM.new("openai/gpt-3.5-turbo", api_key: "test-key")
      module_instance.configure { |config| config.lm = lm_fallback }
      
      strategies_used = []
      
      # Intercept strategy selection to track which ones are used
      allow_any_instance_of(DSPy::LM::StrategySelector).to receive(:select) do |selector|
        strategy = selector.method(:select).super_method.call
        strategies_used << strategy.name
        strategy
      end
      
      allow(lm_fallback.adapter).to receive(:chat).and_return(
        DSPy::LM::Response.new(
          content: '```json\n{"answer": "4", "confidence": 0.9}\n```',
          usage: { prompt_tokens: 20, completion_tokens: 10 },
          metadata: {}
        )
      )
      
      result = module_instance.forward("What is 2+2?")
      
      expect(result.answer).to eq("4")
      expect(strategies_used).to include("enhanced_prompting")
    end
  end
  
  describe "caching" do
    let(:cache_manager) { DSPy::LM.cache_manager }
    
    before do
      cache_manager.clear!
    end
    
    it "caches schema conversions" do
      # First call should generate and cache
      schema1 = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(ReliabilityTestSignature)
      
      # Check it was cached
      expect(cache_manager.stats[:schema_entries]).to eq(1)
      
      # Second call should use cache
      allow(DSPy.logger).to receive(:debug)
      schema2 = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(ReliabilityTestSignature)
      
      expect(DSPy.logger).to have_received(:debug).with(/Using cached schema/)
      expect(schema1).to eq(schema2)
    end
    
    it "caches capability detection" do
      # First call should check and cache
      result1 = DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?("openai/gpt-4o")
      
      # Check it was cached
      expect(cache_manager.stats[:capability_entries]).to eq(1)
      
      # Second call should use cache
      allow(DSPy.logger).to receive(:debug)
      result2 = DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?("openai/gpt-4o")
      
      expect(DSPy.logger).to have_received(:debug).with(/Using cached capability check/)
      expect(result1).to eq(result2)
      expect(result1).to be true
    end
    
    it "uses different cache entries for different models" do
      DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?("openai/gpt-4o")
      DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?("openai/gpt-3.5-turbo")
      
      expect(cache_manager.stats[:capability_entries]).to eq(2)
    end
  end
  
  describe "error handling and graceful degradation" do
    let(:module_instance) { ReliabilityTestModule.new }
    let(:lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: "test-key", structured_outputs: true) }
    
    before do
      module_instance.configure { |config| config.lm = lm }
      DSPy.configure do |config|
        config.lm = lm # Set global LM as fallback
        config.test_mode = true
      end
    end
    
    it "exhausts all strategies before failing", vcr: { cassette_name: "reliability/all_strategies_fail" } do
      strategies_attempted = []
      
      # Mock all strategies to track attempts and fail
      allow_any_instance_of(DSPy::LM::RetryHandler).to receive(:with_retry) do |handler, initial_strategy, &block|
        # Simulate trying all strategies
        %w[openai_structured_output anthropic_extraction enhanced_prompting].each do |strategy_name|
          strategy = instance_double(
            DSPy::LM::Strategies::BaseStrategy,
            name: strategy_name,
            priority: 100 - strategies_attempted.size * 10
          )
          strategies_attempted << strategy_name
          
          begin
            block.call(strategy)
          rescue StandardError
            # Continue to next strategy
          end
        end
        
        raise JSON::ParserError, "All strategies exhausted"
      end
      
      expect do
        module_instance.forward("What is 2+2?")
      end.to raise_error(JSON::ParserError, /All strategies exhausted/)
      
      expect(strategies_attempted).to eq(%w[
        openai_structured_output
        anthropic_extraction
        enhanced_prompting
      ])
    end
    
    it "provides detailed error information" do
      allow(lm.adapter).to receive(:chat).and_return(
        DSPy::LM::Response.new(
          content: "This is not JSON at all",
          usage: { prompt_tokens: 10, completion_tokens: 5 },
          metadata: { model: "gpt-4o-mini" }
        )
      )
      
      # Disable retry for this test
      DSPy.configure { |config| config.structured_outputs.retry_enabled = false }
      
      expect do
        module_instance.forward("What is 2+2?")
      end.to raise_error(RuntimeError) do |error|
        expect(error.message).to include("Failed to parse LLM response as JSON")
        expect(error.message).to include("Original content length: 23 chars")
      end
    end
  end
end