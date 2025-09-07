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
    it "demonstrates basic async LM functionality works" do
      # Test that LM calls work in async context without breaking
      result = nil
      
      Async do
        result = lm.chat(DSPy::ChainOfThought.new(TestSignature), question: "What is 2+2?")
      end
      
      # The basic functionality should work
      expect(result).not_to be_nil
      expect(result.answer).to be_a(String)
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