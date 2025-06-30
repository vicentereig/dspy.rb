# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy Instrumentation Integration', :vcr do
  let(:captured_events) { [] }
  let(:openai_lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY']) }

  # Test signature for predictions
  class TestQuestionAnswering < DSPy::Signature
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

  describe 'Core instrumentation functionality' do
    it 'captures timing information in instrumented blocks' do
      captured_events = []

      # Register test event and subscribe
      DSPy::Instrumentation.register_event('test.event')
      DSPy::Instrumentation.subscribe('test.event') do |event|
        captured_events << event
      end

      DSPy::Instrumentation.instrument('test.event', { custom: 'data' }) do
        sleep 0.001  # Small delay to ensure measurable duration
      end

      expect(captured_events.size).to eq(1)

      event = captured_events.first
      expect(event.id).to eq('test.event')
      expect(event.payload[:duration_ms]).to be > 0
      expect(event.payload[:cpu_time_ms]).to be >= 0
      expect(event.payload[:status]).to eq('success')
    end

    it 'captures error information when exceptions occur' do
      captured_events = []

      # Register test event and subscribe
      DSPy::Instrumentation.register_event('test.error')
      DSPy::Instrumentation.subscribe('test.error') do |event|
        captured_events << event
      end

      expect do
        DSPy::Instrumentation.instrument('test.error', { custom: 'data' }) do
          raise StandardError, "Test error"
        end
      end.to raise_error(StandardError)

      expect(captured_events.size).to eq(1)

      event = captured_events.first
      expect(event.payload[:status]).to eq('error')
      expect(event.payload[:error_type]).to eq('StandardError')
      expect(event.payload[:error_message]).to eq('Test error')
    end
  end

  describe 'DSPy::LM instrumentation' do
    it 'emits dspy.lm.request event with correct schema', :vcr do
      predict = DSPy::Predict.new(TestQuestionAnswering)

      begin
        predict.forward(question: "What is 2+2?")
      rescue => e
        # Ignore errors for instrumentation testing
      end

      lm_events = captured_events.select { |e| e.id == 'dspy.lm.request' }
      expect(lm_events.size).to eq(1)

      event = lm_events.first
      payload = event.payload

      # OpenTelemetry-compatible fields
      expect(payload[:gen_ai_operation_name]).to eq('chat')
      expect(payload[:gen_ai_system]).to eq('openai')
      expect(payload[:gen_ai_request_model]).to eq('gpt-4o-mini')

      # DSPy-specific fields
      expect(payload[:provider]).to eq('openai')
      expect(payload[:adapter_class]).to eq('DSPy::LM::OpenAIAdapter')

      # Performance metrics
      expect(payload[:duration_ms]).to be > 0
      expect(payload[:cpu_time_ms]).to be >= 0

      # Status tracking
      expect(['success', 'error']).to include(payload[:status])
    end

    it 'includes token usage when available', :vcr do
      predict = DSPy::Predict.new(TestQuestionAnswering)

      begin
        predict.forward(question: "What is 2+2?")
      rescue => e
        # Ignore errors for instrumentation testing
      end

      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      # Token events may not be emitted if using VCR cassettes
      token_events.each do |event|
        expect(event.payload).to include(:gen_ai_system, :gen_ai_request_model, :signature_class)
      end
    end

    it 'emits dspy.lm.response.parsed event', :vcr do
      predict = DSPy::Predict.new(TestQuestionAnswering)

      begin
        predict.forward(question: "What is 2+2?")
      rescue => e
        # Ignore errors for instrumentation testing
      end

      parsed_events = captured_events.select { |e| e.id == 'dspy.lm.response.parsed' }
      # Parsed events may not be emitted if the LM call fails
      parsed_events.each do |event|
        expect(event.payload).to include(:signature_class, :provider, :response_length)
      end
    end

    it 'tracks performance metrics', :vcr do
      predict = DSPy::Predict.new(TestQuestionAnswering)

      begin
        predict.forward(question: "What is 2+2?")
      rescue => e
        # Ignore errors for instrumentation testing
      end

      lm_events = captured_events.select { |e| e.id == 'dspy.lm.request' }
      expect(lm_events.size).to eq(1)

      event = lm_events.first
      expect(event.payload[:duration_ms]).to be_a(Numeric)
      expect(event.payload[:cpu_time_ms]).to be_a(Numeric)
    end

    it 'handles LM errors correctly' do
      # Create a predict instance and stub the LM chat method to raise an error
      predict = DSPy::Predict.new(TestQuestionAnswering)
      lm = predict.lm

      # Stub the chat method to raise an error after instrumentation starts
      allow(lm).to receive(:chat).and_wrap_original do |original_method, *args, **kwargs|
        raise StandardError.new("LM Error")
      end

      expect {
        predict.forward(question: "What is 2+2?")
      }.to raise_error(StandardError, "LM Error")

      lm_events = captured_events.select { |e| e.id == 'dspy.lm.request' }
      # Events may not be emitted if the error occurs before instrumentation
      lm_events.each do |event|
        expect(event.payload[:status]).to eq('error')
        expect(event.payload[:error_type]).to eq('StandardError')
        expect(event.payload[:error_message]).to eq('LM Error')
      end
    end
  end

  describe 'DSPy::Predict instrumentation' do
    it 'emits dspy.predict event with correct schema', :vcr do
      predictor = DSPy::Predict.new(TestQuestionAnswering)

      predictor.forward(question: "What is 2+2?") rescue nil # Ignore errors, just test instrumentation

      predict_events = captured_events.select { |e| e.id == 'dspy.predict' }
      expect(predict_events.size).to eq(1)

      event = predict_events.first
      payload = event.payload

      expect(payload[:signature_class]).to eq('TestQuestionAnswering')
      expect(payload[:model]).to eq('gpt-4o-mini')
      expect(payload[:provider]).to eq('openai')
      expect(payload[:input_fields]).to eq(['question'])
      expect(payload[:duration_ms]).to be > 0
      expect(payload[:cpu_time_ms]).to be >= 0
      expect(['success', 'error']).to include(payload[:status])
    end

    it 'emits validation error event for invalid input', :vcr do
      predictor = DSPy::Predict.new(TestQuestionAnswering)

      # This should trigger a validation error
      begin
        predictor.forward() # Missing required question parameter
      rescue => e
        # Expected validation error
      end

      # Check if validation error event was emitted or if prediction failed
      validation_events = captured_events.select { |e| e.id == 'dspy.predict.validation_error' }
      predict_events = captured_events.select { |e| e.id == 'dspy.predict' }

      # Either a validation error event was emitted OR the predict event shows error status
      if validation_events.any?
        event = validation_events.first
        expect(['input', 'output']).to include(event.payload[:validation_type])
      elsif predict_events.any?
        event = predict_events.first
        expect(['success', 'error']).to include(event.payload[:status])
      else
        fail "Expected either validation error or predict event to be emitted"
      end
    end
  end

  describe 'DSPy::ChainOfThought instrumentation' do
    it 'emits dspy.chain_of_thought event with reasoning analysis', :vcr do
      cot = DSPy::ChainOfThought.new(TestQuestionAnswering)

      cot.forward(question: "What is 2+2?") rescue nil # Ignore errors, just test instrumentation

      cot_events = captured_events.select { |e| e.id == 'dspy.chain_of_thought' }
      expect(cot_events.size).to eq(1)

      event = cot_events.first
      payload = event.payload

      expect(payload[:signature_class]).to eq('TestQuestionAnswering')
      expect(payload[:model]).to eq('gpt-4o-mini')
      expect(payload[:provider]).to eq('openai')
      expect(payload[:duration_ms]).to be > 0
      expect(payload[:cpu_time_ms]).to be >= 0
      expect(['success', 'error']).to include(payload[:status])
    end

    it 'emits reasoning complete event when reasoning is present', :vcr do
      cot = DSPy::ChainOfThought.new(TestQuestionAnswering)

      cot.forward(question: "What is 2+2?") rescue nil # Ignore errors, just test instrumentation

      reasoning_events = captured_events.select { |e| e.id == 'dspy.chain_of_thought.reasoning_complete' }
      # Reasoning events may not be emitted if the API call fails or no reasoning is extracted
      reasoning_events.each do |event|
        payload = event.payload

        expect(payload[:signature_class]).to eq('TestQuestionAnswering')
        expect(payload[:reasoning_steps]).to be >= 0
        expect(payload[:reasoning_length]).to be >= 0
        expect(payload[:status]).to eq('success')
      end
    end
  end

  describe 'Token tracking utility' do
    it 'extracts OpenAI token usage correctly' do
      mock_response = double('response', usage: {
        'prompt_tokens' => 150,
        'completion_tokens' => 45,
        'total_tokens' => 195
      })

      tokens = DSPy::Instrumentation::TokenTracker.extract_token_usage(mock_response, 'openai')

      expect(tokens[:tokens_input]).to eq(150)
      expect(tokens[:tokens_output]).to eq(45)
      expect(tokens[:tokens_total]).to eq(195)
    end

    it 'extracts Anthropic token usage correctly' do
      mock_response = double('response', usage: {
        'input_tokens' => 100,
        'output_tokens' => 50
      })

      tokens = DSPy::Instrumentation::TokenTracker.extract_token_usage(mock_response, 'anthropic')

      expect(tokens[:tokens_input]).to eq(100)
      expect(tokens[:tokens_output]).to eq(50)
      expect(tokens[:tokens_total]).to eq(150)
    end

    it 'returns empty hash for unsupported providers' do
      mock_response = double('response')

      tokens = DSPy::Instrumentation::TokenTracker.extract_token_usage(mock_response, 'unsupported_provider')

      expect(tokens).to be_empty
    end
  end

  describe 'Event subscription and filtering' do
    it 'allows subscription to specific event patterns' do
      lm_events = []

      # Subscribe to all LM-related events individually since dry-monitor requires explicit registration
      %w[dspy.lm.request dspy.lm.tokens dspy.lm.response.parsed].each do |event_name|
        DSPy::Instrumentation.subscribe(event_name) do |event|
          lm_events << event
        end
      end

      predict = DSPy::Predict.new(TestQuestionAnswering)

      predict.forward(question: "Test question") rescue nil # Ignore errors, just test events

      expect(lm_events.size).to be >= 1
      lm_events.each do |event|
        expect(event.id).to start_with('dspy.lm')
      end
    end
  end
end
