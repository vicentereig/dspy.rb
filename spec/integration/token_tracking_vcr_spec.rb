# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Token tracking with VCR', :vcr do
  let(:openai_lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY']) }
  let(:anthropic_lm) { DSPy::LM.new("anthropic/claude-3-haiku-20240307", api_key: ENV['ANTHROPIC_API_KEY']) }
  let(:captured_events) { [] }

  # Test signature for token tracking
  class SimpleQuestion < DSPy::Signature
    description "Answer simple questions"

    input do
      const :question, String
    end

    output do
      const :answer, String
    end
  end

  before do
    # Enable instrumentation
    DSPy.configure do |config|
      config.instrumentation.enabled = true
    end

    # Setup subscribers
    DSPy::Instrumentation.setup_subscribers
    
    # Capture all events for debugging
    DSPy::Instrumentation.subscribe do |event|
      captured_events << event
    end
  end

  after do
    captured_events.clear
  end

  describe 'OpenAI token tracking' do
    it 'captures token usage when using VCR cassettes' do
      DSPy.configure do |config|
        config.lm = openai_lm
      end

      predict = DSPy::Predict.new(SimpleQuestion)
      
      # Make the API call
      result = predict.forward(question: "What is 1+1?")
      
      # Verify response
      expect(result.answer).to be_a(String)
      expect(result.answer).not_to be_empty
      
      # Verify token event was captured
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      expect(token_events).not_to be_empty
      
      token_event = token_events.first
      expect(token_event.payload).to include(
        :input_tokens,
        :output_tokens,
        :total_tokens,
        :gen_ai_system,
        :gen_ai_request_model,
        :signature_class
      )
      
      # Verify token counts are reasonable
      expect(token_event.payload[:input_tokens]).to be > 0
      expect(token_event.payload[:output_tokens]).to be > 0
      expect(token_event.payload[:total_tokens]).to eq(
        token_event.payload[:input_tokens] + token_event.payload[:output_tokens]
      )
      
      # Verify metadata
      expect(token_event.payload[:gen_ai_system]).to eq('openai')
      expect(token_event.payload[:gen_ai_request_model]).to eq('gpt-4o-mini')
      expect(token_event.payload[:signature_class]).to eq('SimpleQuestion')
    end

    it 'captures token usage with structured outputs enabled' do
      # Create LM with structured outputs
      structured_lm = DSPy::LM.new(
        "openai/gpt-4o-mini", 
        api_key: ENV['OPENAI_API_KEY'],
        structured_outputs: true
      )
      
      DSPy.configure do |config|
        config.lm = structured_lm
      end

      predict = DSPy::Predict.new(SimpleQuestion)
      
      # Make the API call
      result = predict.forward(question: "What is 2+2?")
      
      # Verify token event was captured even with structured outputs
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      expect(token_events).not_to be_empty
      
      token_event = token_events.first
      expect(token_event.payload[:input_tokens]).to be > 0
      expect(token_event.payload[:output_tokens]).to be > 0
    end
  end

  describe 'Anthropic token tracking' do
    it 'captures token usage when using VCR cassettes' do
      DSPy.configure do |config|
        config.lm = anthropic_lm
      end

      predict = DSPy::Predict.new(SimpleQuestion)
      
      # Make the API call
      result = predict.forward(question: "What is 3+3?")
      
      # Verify response
      expect(result.answer).to be_a(String)
      expect(result.answer).not_to be_empty
      
      # Verify token event was captured
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      expect(token_events).not_to be_empty
      
      token_event = token_events.first
      expect(token_event.payload).to include(
        :input_tokens,
        :output_tokens,
        :total_tokens,
        :gen_ai_system,
        :gen_ai_request_model,
        :signature_class
      )
      
      # Verify token counts
      expect(token_event.payload[:input_tokens]).to be > 0
      expect(token_event.payload[:output_tokens]).to be > 0
      expect(token_event.payload[:total_tokens]).to eq(
        token_event.payload[:input_tokens] + token_event.payload[:output_tokens]
      )
      
      # Verify metadata
      expect(token_event.payload[:gen_ai_system]).to eq('anthropic')
      expect(token_event.payload[:gen_ai_request_model]).to eq('claude-3-haiku-20240307')
      expect(token_event.payload[:signature_class]).to eq('SimpleQuestion')
    end
  end

  describe 'Token tracking edge cases' do
    it 'handles missing usage data gracefully' do
      # Mock a response without usage data
      allow_any_instance_of(DSPy::LM::OpenAIAdapter).to receive(:chat).and_return(
        DSPy::LM::Response.new(
          content: '{"answer": "test"}',
          usage: nil,
          metadata: { provider: 'openai', model: 'gpt-4o-mini' }
        )
      )
      
      DSPy.configure do |config|
        config.lm = openai_lm
      end

      predict = DSPy::Predict.new(SimpleQuestion)
      
      # Should not raise error
      expect {
        predict.forward(question: "Test question")
      }.not_to raise_error
      
      # No token event should be emitted
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      expect(token_events).to be_empty
    end
  end
end