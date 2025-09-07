# frozen_string_literal: true

require "spec_helper"
require 'async'

RSpec.describe "Async Retry Behavior", :integration do
  let(:lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'] || 'test-key') }
  
  class TestSignature < DSPy::Signature
    description "Simple test signature for async retry testing"
    
    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end
  
  before do
    # Enable retries but disable test_mode to see the actual sleep behavior
    DSPy.config.structured_outputs.retry_enabled = true
    DSPy.config.test_mode = false
  end
  
  after do
    DSPy.config.test_mode = true
  end
  
  describe "retry blocking behavior" do
    it "demonstrates that retries currently block the entire thread" do
      skip "This test will fail until we implement async retry handling"
      
      # Create a scenario where retry will happen with actual backoff
      start_time = Time.now
      concurrent_results = []
      
      # This should demonstrate that multiple LM calls can't run concurrently 
      # due to blocking sleep in retry logic
      Async do
        tasks = 3.times.map do |i|
          Async do
            # Mock adapter to simulate failures that trigger retries
            adapter = lm.instance_variable_get(:@adapter)
            allow(adapter).to receive(:chat).and_raise(JSON::ParserError, "Invalid JSON").twice
              .then.return(DSPy::LM::Response.new(
                content: "{\"answer\": \"Result #{i}\"}",
                usage: DSPy::LM::Usage.new(input_tokens: 10, output_tokens: 10, total_tokens: 20)
              ))
            
            result = lm.chat(DSPy::ChainOfThought.new(TestSignature), question: "What is #{i}?")
            concurrent_results << { index: i, result: result.answer, time: Time.now - start_time }
            result
          end
        end
        
        tasks.map(&:wait)
      end
      
      # If retries are blocking, the total time should be much longer
      # because each retry sleeps sequentially rather than concurrently
      total_time = Time.now - start_time
      
      # With proper async behavior, all 3 calls should run concurrently
      # even with retries, so total time should be close to the time of a single retry sequence
      expect(total_time).to be < 3.0  # This will fail with current blocking implementation
      expect(concurrent_results).to have(3).items
    end
  end
  
  describe "proper async context detection" do
    it "should detect when running in an async context" do
      in_async_context = false
      
      Async do
        # Check if we can detect async context
        in_async_context = !!(defined?(Async::Task) && Async::Task.current?)
      end
      
      expect(in_async_context).to be true
    end
    
    it "should not detect async context when not in Async block" do
      in_async_context = !!(defined?(Async::Task) && Async::Task.current?)
      expect(in_async_context).to be false
    end
  end
end