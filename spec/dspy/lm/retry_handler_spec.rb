# frozen_string_literal: true

require "spec_helper"

# Test adapter for Sorbet compatibility
class RetryHandlerTestAdapter < DSPy::LM::Adapter
  def initialize
    # Skip parent initialization for tests
    @model = "test-model"
    @api_key = "test-key"
  end
  
  def chat(messages:, &block)
    # Not used in these tests
  end
end

# Test strategies for mocking
class TestOpenAIStrategy < DSPy::LM::Strategies::BaseStrategy
  def name; "openai_structured_output"; end
  def priority; 100; end
  def available?; true; end
  def prepare_request(messages, request_params); end
  def extract_json(response); response.content; end
  def handle_error(error); false; end
end

class TestAnthropicStrategy < DSPy::LM::Strategies::BaseStrategy
  def name; "anthropic_extraction"; end
  def priority; 90; end
  def available?; true; end
  def prepare_request(messages, request_params); end
  def extract_json(response); response.content; end
  def handle_error(error); false; end
end

class TestEnhancedStrategy < DSPy::LM::Strategies::BaseStrategy
  def name; "enhanced_prompting"; end
  def priority; 50; end
  def available?; true; end
  def prepare_request(messages, request_params); end
  def extract_json(response); response.content; end
  def handle_error(error); false; end
end

RSpec.describe DSPy::LM::RetryHandler do
  let(:adapter) { RetryHandlerTestAdapter.new }
  let(:signature_class) do
    Class.new(DSPy::Signature) do
      def self.name
        "TestSignature"
      end
    end
  end
  let(:retry_handler) { described_class.new(adapter, signature_class) }
  
  # Use real strategy instances for Sorbet compatibility
  let(:openai_strategy) { TestOpenAIStrategy.new(adapter, signature_class) }
  let(:anthropic_strategy) { TestAnthropicStrategy.new(adapter, signature_class) }
  let(:enhanced_strategy) { TestEnhancedStrategy.new(adapter, signature_class) }
  
  before do
    # Mock strategy selector to return our test strategies
    strategy_selector = instance_double(DSPy::LM::StrategySelector)
    allow(DSPy::LM::StrategySelector).to receive(:new).with(adapter, signature_class)
      .and_return(strategy_selector)
    allow(strategy_selector).to receive(:available_strategies)
      .and_return([openai_strategy, anthropic_strategy, enhanced_strategy])
  end
  
  describe "#with_retry" do
    context "when the first attempt succeeds" do
      it "returns the result without retrying" do
        result = { answer: "42" }
        
        executed_strategies = []
        returned_result = retry_handler.with_retry(openai_strategy) do |strategy|
          executed_strategies << strategy.name
          result
        end
        
        expect(returned_result).to eq(result)
        expect(executed_strategies).to eq(["openai_structured_output"])
      end
    end
    
    context "when JSON parsing fails" do
      it "retries with the same strategy before trying fallback" do
        executed_strategies = []
        attempt_counts = Hash.new(0)
        
        # Enable retries to test retry behavior
        allow(DSPy.config.structured_outputs).to receive(:retry_enabled).and_return(true)
        
        Sync do
          returned_result = retry_handler.with_retry(openai_strategy) do |strategy|
            executed_strategies << strategy.name
            attempt_counts[strategy.name] += 1
            
            if strategy == openai_strategy && attempt_counts[strategy.name] < 2
              raise JSON::ParserError, "Invalid JSON"
            else
              { answer: "Success" }
            end
          end
          
          expect(returned_result).to eq({ answer: "Success" })
          expect(executed_strategies).to eq(["openai_structured_output", "openai_structured_output"])
          expect(attempt_counts["openai_structured_output"]).to eq(2)
        end
      end
      
      it "falls back to next strategy after max retries" do
        executed_strategies = []
        
        # Enable retries to test fallback behavior
        allow(DSPy.config.structured_outputs).to receive(:retry_enabled).and_return(true)
        
        Sync do
          returned_result = retry_handler.with_retry(openai_strategy) do |strategy|
            executed_strategies << strategy.name
            
            if strategy == openai_strategy
              raise JSON::ParserError, "Invalid JSON"
            else
              { answer: "Success with fallback" }
            end
          end
          
          expect(returned_result).to eq({ answer: "Success with fallback" })
          # Should try openai twice (1 initial + 1 retry), then anthropic
          expect(executed_strategies).to eq([
            "openai_structured_output",
            "openai_structured_output", 
            "anthropic_extraction"
          ])
        end
      end
    end
    
    context "when strategy handles the error" do
      it "moves to next strategy without retrying" do
        # Create a custom strategy that can handle errors
        handling_strategy = Class.new(TestOpenAIStrategy) do
          def handle_error(error)
            true
          end
        end.new(adapter, signature_class)
        
        executed_strategies = []
        
        returned_result = retry_handler.with_retry(handling_strategy) do |strategy|
          executed_strategies << strategy.name
          
          if strategy.name == "openai_structured_output"
            raise StandardError, "API Error"
          else
            { answer: "Success" }
          end
        end
        
        expect(returned_result).to eq({ answer: "Success" })
        # Should only try openai once, then move to anthropic
        expect(executed_strategies).to eq(["openai_structured_output", "anthropic_extraction"])
      end
    end
    
    context "when all strategies fail" do
      it "raises the last error" do
        # Enable retries to test fallback behavior
        allow(DSPy.config.structured_outputs).to receive(:retry_enabled).and_return(true)
        
        Sync do
          expect do
            retry_handler.with_retry(openai_strategy) do |strategy|
              raise JSON::ParserError, "Failed with #{strategy.name}"
            end
          end.to raise_error(JSON::ParserError, /Failed with enhanced_prompting/)
        end
      end
    end
    
    context "with different retry counts per strategy" do
      it "uses fewer retries for structured output strategy" do
        attempt_counts = Hash.new(0)
        # Enable retries to test fallback behavior
        allow(DSPy.config.structured_outputs).to receive(:retry_enabled).and_return(true)
        
        Sync do
          begin
            retry_handler.with_retry(openai_strategy) do |strategy|
              attempt_counts[strategy.name] += 1
              raise JSON::ParserError, "Always fail"
            end
          rescue JSON::ParserError
            # Expected
          end
          
          # OpenAI gets 1 retry (2 total attempts)
          expect(attempt_counts["openai_structured_output"]).to eq(2)
          # Anthropic gets 2 retries (3 total attempts)  
          expect(attempt_counts["anthropic_extraction"]).to eq(3)
          # Enhanced gets 3 retries (4 total attempts)
          expect(attempt_counts["enhanced_prompting"]).to eq(4)
        end
      end
    end
    
    context "backoff calculation" do
      it "calculates exponential backoff with jitter" do
        # Access private method for testing
        backoff1 = retry_handler.send(:calculate_backoff, 1)
        backoff2 = retry_handler.send(:calculate_backoff, 2)
        backoff3 = retry_handler.send(:calculate_backoff, 3)
        
        expect(backoff1).to be_between(0.5, 0.55)  # Base + jitter
        expect(backoff2).to be_between(1.0, 1.1)   # 2x base + jitter
        expect(backoff3).to be_between(2.0, 2.2)   # 4x base + jitter
        
        # Test cap at 10 seconds
        backoff_large = retry_handler.send(:calculate_backoff, 10)
        expect(backoff_large).to be <= 10.0
      end
    end
  end
  
  describe "fallback chain construction" do
    it "builds a chain starting with requested strategy" do
      # Access private method for testing
      chain = retry_handler.send(:build_fallback_chain, anthropic_strategy)
      
      expect(chain.map(&:name)).to eq([
        "anthropic_extraction",    # Requested strategy first
        "openai_structured_output", # Then by priority
        "enhanced_prompting"
      ])
    end
    
    it "excludes unavailable strategies" do
      # Create a strategy that's not available
      unavailable_strategy = Class.new(TestAnthropicStrategy) do
        def available?
          false
        end
      end.new(adapter, signature_class)
      
      # Update mock to exclude unavailable strategy
      strategy_selector = instance_double(DSPy::LM::StrategySelector)
      allow(DSPy::LM::StrategySelector).to receive(:new).with(adapter, signature_class)
        .and_return(strategy_selector)
      allow(strategy_selector).to receive(:available_strategies)
        .and_return([openai_strategy, enhanced_strategy])
      
      chain = retry_handler.send(:build_fallback_chain, openai_strategy)
      
      expect(chain.map(&:name)).to eq([
        "openai_structured_output",
        "enhanced_prompting"
      ])
    end
  end
end