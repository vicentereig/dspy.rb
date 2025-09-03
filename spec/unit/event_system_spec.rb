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

  describe 'Event Listener System' do
    describe '.events' do
      after do
        # Clean up listeners after each test
        DSPy.events.clear_listeners
      end

      it 'returns an event registry object' do
        expect(DSPy.events).to respond_to(:subscribe)
        expect(DSPy.events).to respond_to(:unsubscribe)
        expect(DSPy.events).to respond_to(:clear_listeners)
      end
    end

    describe '.events.subscribe' do
      after do
        DSPy.events.clear_listeners
      end

      it 'registers a listener for exact event names' do
        received_events = []
        
        DSPy.events.subscribe('llm.response') do |event_name, attributes|
          received_events << [event_name, attributes]
        end
        
        DSPy.event('llm.response', provider: 'openai')
        DSPy.event('other.event', data: 'ignored')
        
        expect(received_events.length).to eq(1)
        expect(received_events[0][0]).to eq('llm.response')
        expect(received_events[0][1][:provider]).to eq('openai')
      end
      
      it 'registers a listener for pattern matching with wildcards' do
        received_events = []
        
        DSPy.events.subscribe('llm.*') do |event_name, attributes|
          received_events << [event_name, attributes]
        end
        
        DSPy.event('llm.response', provider: 'openai')
        DSPy.event('llm.request', model: 'gpt-4')
        DSPy.event('module.forward', data: 'ignored')
        
        expect(received_events.length).to eq(2)
        expect(received_events.map { |e| e[0] }).to match_array(['llm.response', 'llm.request'])
      end
      
      it 'supports multiple listeners for the same event' do
        listener1_calls = []
        listener2_calls = []
        
        DSPy.events.subscribe('test.event') do |event_name, attributes|
          listener1_calls << [event_name, attributes]
        end
        
        DSPy.events.subscribe('test.event') do |event_name, attributes|
          listener2_calls << [event_name, attributes]
        end
        
        DSPy.event('test.event', data: 'value')
        
        expect(listener1_calls.length).to eq(1)
        expect(listener2_calls.length).to eq(1)
        expect(listener1_calls[0]).to eq(listener2_calls[0])
      end
      
      it 'returns a subscription ID for later unsubscription' do
        subscription_id = DSPy.events.subscribe('test.event') do |event_name, attributes|
          # listener block
        end
        
        expect(subscription_id).to be_a(String)
        expect(subscription_id).not_to be_empty
      end
    end

    describe '.events.unsubscribe' do
      after do
        DSPy.events.clear_listeners
      end

      it 'removes a specific listener by subscription ID' do
        received_events = []
        
        subscription_id = DSPy.events.subscribe('test.event') do |event_name, attributes|
          received_events << [event_name, attributes]
        end
        
        DSPy.event('test.event', data: 'before_unsubscribe')
        expect(received_events.length).to eq(1)
        
        DSPy.events.unsubscribe(subscription_id)
        DSPy.event('test.event', data: 'after_unsubscribe')
        expect(received_events.length).to eq(1) # Should not increase
      end
    end

    describe 'error handling in listeners' do
      after do
        DSPy.events.clear_listeners
      end

      it 'continues processing other listeners if one fails' do
        successful_listener_calls = []
        
        # First listener that will fail
        DSPy.events.subscribe('test.event') do |event_name, attributes|
          raise StandardError, "Listener failure"
        end
        
        # Second listener that should still get called
        DSPy.events.subscribe('test.event') do |event_name, attributes|
          successful_listener_calls << [event_name, attributes]
        end
        
        # Should not raise an error and should call the successful listener
        expect {
          DSPy.event('test.event', data: 'value')
        }.not_to raise_error
        
        expect(successful_listener_calls.length).to eq(1)
      end
    end
  end
end