# frozen_string_literal: true

require "spec_helper"
require 'async'

RSpec.describe "Async Retry Behavior", :integration do
  let(:lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY']) }
  
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
    it "demonstrates basic async LM functionality works", vcr: { cassette_name: "async_basic_lm_call" } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Test that LM calls work in async context without breaking
      result = Async do
        lm.chat(DSPy::ChainOfThought.new(TestSignature), question: "What is 2+2?")
      end.wait
      
      # The basic functionality should work
      expect(result).not_to be_nil
      # Should be a Prediction object with an answer
      if result.respond_to?(:answer)
        expect(result.answer).to be_a(String)
      else
        # If it's a Hash, check that too
        expect(result).to be_a(Hash)
        expect(result[:answer] || result['answer']).to be_a(String)
      end
    end
  end
  
  describe "proper async context detection" do
    it "should detect when running in an async context" do
      in_async_context = false
      
      Async do
        # Check if we can detect async context
        in_async_context = !!(defined?(Async::Task) && Async::Task.current?)
      end.wait
      
      expect(in_async_context).to be true
    end
    
    it "should not detect async context when not in Async block" do
      in_async_context = !!(defined?(Async::Task) && Async::Task.current?)
      expect(in_async_context).to be false
    end
  end
end