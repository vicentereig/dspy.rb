# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy Event System' do
  describe '.event' do
    context 'basic event emission' do
      it 'emits an event with name and attributes' do
        # Capture logger output to verify the event is logged
        logger_output = StringIO.new
        test_logger = Dry.Logger(:test, formatter: :string) do |config|
          config.add_backend(stream: logger_output)
        end
        
        allow(DSPy).to receive(:logger).and_return(test_logger)
        
        # This should work like DSPy.log but with event-specific behavior
        DSPy.event('llm.response', {
          provider: 'openai',
          model: 'gpt-4',
          usage: { prompt_tokens: 100, completion_tokens: 50 },
          duration_ms: 1250
        })
        
        # Verify the event was logged with proper format
        log_output = logger_output.string
        expect(log_output).to include('event="llm.response"')
        expect(log_output).to include('provider="openai"')
        expect(log_output).to include('model="gpt-4"')
        expect(log_output).to include('duration_ms=1250')
      end
      
      it 'includes trace context when called within a span' do
        logger_output = StringIO.new
        test_logger = Dry.Logger(:test, formatter: :string) do |config|
          config.add_backend(stream: logger_output)
        end
        
        allow(DSPy).to receive(:logger).and_return(test_logger)
        
        DSPy::Context.with_span(operation: 'test_operation') do
          DSPy.event('test.event', data: 'value')
        end
        
        log_output = logger_output.string
        expect(log_output).to include('event="test.event"')
        expect(log_output).to include('data="value"')
        expect(log_output).to include('trace_id=')
      end
      
      it 'works without a span context' do
        logger_output = StringIO.new
        test_logger = Dry.Logger(:test, formatter: :string) do |config|
          config.add_backend(stream: logger_output)
        end
        
        allow(DSPy).to receive(:logger).and_return(test_logger)
        
        # Should not raise an error when called outside of span
        expect {
          DSPy.event('standalone.event', message: 'hello')
        }.not_to raise_error
        
        log_output = logger_output.string
        expect(log_output).to include('event="standalone.event"')
        expect(log_output).to include('hello')
      end
    end
    
    context 'error handling' do
      it 'handles nil attributes gracefully' do
        expect {
          DSPy.event('test.event', nil)
        }.not_to raise_error
      end
      
      it 'handles empty attributes hash' do
        expect {
          DSPy.event('test.event', {})
        }.not_to raise_error
      end
      
      it 'requires an event name' do
        expect {
          DSPy.event(nil, data: 'value')
        }.to raise_error(ArgumentError)
      end
    end
  end
end