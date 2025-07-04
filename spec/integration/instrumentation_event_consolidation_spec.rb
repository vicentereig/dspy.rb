# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Instrumentation Event Consolidation', :vcr do
  let(:captured_events) { [] }
  let(:openai_lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY']) }

  # Test signature for predictions
  class TestEventConsolidation < DSPy::Signature
    description "Answer questions accurately and helpfully"

    input do
      const :question, String, description: "A question to answer"
    end

    output do
      const :answer, String, description: "A helpful answer to the question"
    end
  end

  before do
    # Capture all events for testing
    DSPy::Instrumentation.subscribe do |event|
      captured_events << event
    end

    # Configure DSPy with test LM
    DSPy.configure do |config|
      config.lm = openai_lm
    end
  end

  after do
    captured_events.clear
  end

  describe 'event consolidation behavior' do
    it 'emits fewer events in standard mode compared to detailed mode for ChainOfThought', :vcr do
      # Test with detailed mode first
      DSPy.config.instrumentation.trace_level = :detailed
      cot_detailed = DSPy::ChainOfThought.new(TestEventConsolidation)
      
      cot_detailed.forward(question: "What is 2+2?") rescue nil
      detailed_events = captured_events.map(&:id)
      captured_events.clear
      
      # Test with standard mode
      DSPy.config.instrumentation.trace_level = :standard
      cot_standard = DSPy::ChainOfThought.new(TestEventConsolidation)
      
      cot_standard.forward(question: "What is 2+2?") rescue nil
      standard_events = captured_events.map(&:id)
      captured_events.clear
      
      # Test with minimal mode
      DSPy.config.instrumentation.trace_level = :minimal
      cot_minimal = DSPy::ChainOfThought.new(TestEventConsolidation)
      
      cot_minimal.forward(question: "What is 2+2?") rescue nil
      minimal_events = captured_events.map(&:id)
      
      # Verify event consolidation is working
      expect(detailed_events.size).to be > standard_events.size
      expect(standard_events.size).to be >= minimal_events.size  # Can be equal for top-level calls
      
      # Detailed mode should have all events
      expect(detailed_events).to include('dspy.chain_of_thought', 'dspy.predict', 'dspy.lm.request')
      
      # Standard mode should skip nested events for ChainOfThought
      expect(standard_events).to include('dspy.chain_of_thought')
      expect(standard_events).not_to include('dspy.predict', 'dspy.lm.request')
      
      # Minimal mode should only have top-level events
      expect(minimal_events).to include('dspy.chain_of_thought')
      expect(minimal_events).not_to include('dspy.predict', 'dspy.lm.request')
      
      # Both standard and minimal should emit the same events for ChainOfThought
      expect(standard_events).to eq(minimal_events)
    end

    it 'emits all events in standard mode for direct Predict calls', :vcr do
      DSPy.config.instrumentation.trace_level = :standard
      predict = DSPy::Predict.new(TestEventConsolidation)
      
      predict.forward(question: "What is 2+2?") rescue nil
      events = captured_events.map(&:id)
      
      # For direct Predict calls (not nested), should emit all events
      expect(events).to include('dspy.predict', 'dspy.lm.request')
    end
  end

  describe 'timestamp format configuration' do
    it 'generates timestamps in ISO8601 format by default' do
      DSPy.config.instrumentation.timestamp_format = DSPy::TimestampFormat::ISO8601
      
      predict = DSPy::Predict.new(TestEventConsolidation)
      predict.forward(question: "What is 2+2?") rescue nil
      
      event = captured_events.first
      expect(event.payload[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[Z+-]/)
    end

    it 'generates timestamps in Unix nanoseconds format when configured' do
      DSPy.config.instrumentation.timestamp_format = DSPy::TimestampFormat::UNIX_NANO
      
      predict = DSPy::Predict.new(TestEventConsolidation)
      predict.forward(question: "What is 2+2?") rescue nil
      
      event = captured_events.first
      expect(event.payload[:timestamp_ns]).to be_a(Integer)
      expect(event.payload[:timestamp_ns]).to be > 1_000_000_000_000_000_000 # Reasonable Unix nanosecond timestamp
    end

    it 'generates timestamps in RFC3339 nanosecond format when configured' do
      DSPy.config.instrumentation.timestamp_format = DSPy::TimestampFormat::RFC3339_NANO
      
      predict = DSPy::Predict.new(TestEventConsolidation)
      predict.forward(question: "What is 2+2?") rescue nil
      
      event = captured_events.first
      expect(event.payload[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}[+-]\d{4}/)
    end
  end

  describe 'token reporting standardization' do
    it 'reports tokens in standardized format across providers', :vcr do
      predict = DSPy::Predict.new(TestEventConsolidation)
      predict.forward(question: "What is 2+2?") rescue nil
      
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      
      if token_events.any?
        token_event = token_events.first
        payload = token_event.payload
        
        # Should use standardized field names
        expect(payload.keys).to include(:input_tokens, :output_tokens, :total_tokens)
        expect(payload.keys).not_to include(:tokens_input, :tokens_output, :tokens_total)
      end
    end
  end
end