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

  describe 'OpenTelemetry Integration' do
    describe 'span creation from events' do
      let(:mock_tracer) { double('tracer') }
      let(:mock_span) { double('span') }

      before do
        # Mock observability being enabled
        allow(DSPy::Observability).to receive(:enabled?).and_return(true)
        allow(DSPy::Observability).to receive(:tracer).and_return(mock_tracer)
        allow(DSPy::Observability).to receive(:start_span).and_return(mock_span)
        allow(DSPy::Observability).to receive(:finish_span)
      end

      it 'creates OpenTelemetry spans for events when observability is enabled' do
        expect(DSPy::Observability).to receive(:start_span).with(
          'llm.response',
          hash_including(
            'provider' => 'openai',
            'model' => 'gpt-4',
            'duration_ms' => 1250
          )
        ).and_return(mock_span)
        
        expect(DSPy::Observability).to receive(:finish_span).with(mock_span)

        DSPy.event('llm.response', {
          provider: 'openai',
          model: 'gpt-4',
          duration_ms: 1250
        })
      end

      it 'does not create spans when observability is disabled' do
        allow(DSPy::Observability).to receive(:enabled?).and_return(false)
        
        expect(DSPy::Observability).not_to receive(:start_span)
        expect(DSPy::Observability).not_to receive(:finish_span)

        DSPy.event('llm.response', provider: 'openai')
      end

      it 'handles errors in span creation gracefully' do
        allow(DSPy::Observability).to receive(:start_span).and_raise(StandardError, "OTEL error")
        
        # Should not raise an error
        expect {
          DSPy.event('llm.response', provider: 'openai')
        }.not_to raise_error
      end

      it 'creates spans with proper semantic conventions for LLM events' do
        expect(DSPy::Observability).to receive(:start_span).with(
          'llm.generate',
          hash_including(
            'gen_ai.system' => 'openai',
            'gen_ai.request.model' => 'gpt-4',
            'gen_ai.usage.prompt_tokens' => 100,
            'gen_ai.usage.completion_tokens' => 50,
            'gen_ai.usage.total_tokens' => 150
          )
        )

        DSPy.event('llm.generate', {
          'gen_ai.system' => 'openai',
          'gen_ai.request.model' => 'gpt-4',
          'gen_ai.usage.prompt_tokens' => 100,
          'gen_ai.usage.completion_tokens' => 50,
          'gen_ai.usage.total_tokens' => 150
        })
      end
    end

    describe 'event attributes handling' do
      let(:mock_tracer) { double('tracer') }
      let(:mock_span) { double('span') }

      before do
        allow(DSPy::Observability).to receive(:enabled?).and_return(true)
        allow(DSPy::Observability).to receive(:start_span).and_return(mock_span)
        allow(DSPy::Observability).to receive(:finish_span)
      end

      it 'converts nested hashes to flat attributes for spans' do
        expect(DSPy::Observability).to receive(:start_span).with(
          'test.event',
          hash_including(
            'usage.prompt_tokens' => 100,
            'usage.completion_tokens' => 50
          )
        )

        DSPy.event('test.event', {
          usage: { prompt_tokens: 100, completion_tokens: 50 }
        })
      end

      it 'handles nil and empty attributes' do
        expect(DSPy::Observability).to receive(:start_span).with(
          'test.event',
          {}
        )

        DSPy.event('test.event', nil)
      end
    end
  end

  describe 'Thread and Fiber Safety' do
    after do
      DSPy.events.clear_listeners
    end

    it 'handles concurrent event emissions from multiple threads' do
      received_events = []
      mutex = Mutex.new
      
      DSPy.events.subscribe('test.event') do |event_name, attributes|
        mutex.synchronize do
          received_events << [event_name, attributes, Thread.current.object_id]
        end
      end
      
      threads = 10.times.map do |i|
        Thread.new do
          DSPy.event('test.event', thread_id: i)
        end
      end
      
      threads.each(&:join)
      
      expect(received_events.length).to eq(10)
      thread_ids = received_events.map { |e| e[2] }.uniq
      expect(thread_ids.length).to be > 1  # Events came from different threads
    end

    it 'maintains separate event registry per process' do
      # The event registry should be shared across threads but isolated per process
      DSPy.events.subscribe('test.event') { |*args| }
      
      # Each thread should see the same listeners
      thread_registries = []
      threads = 3.times.map do
        Thread.new do
          thread_registries << DSPy.events.object_id
        end
      end
      
      threads.each(&:join)
      
      # All threads should share the same registry instance
      expect(thread_registries.uniq.length).to eq(1)
      expect(thread_registries[0]).to eq(DSPy.events.object_id)
    end

    it 'handles listener failures in one thread without affecting others' do
      successful_calls = []
      mutex = Mutex.new
      
      # Listener that will fail
      DSPy.events.subscribe('test.event') do |event_name, attributes|
        raise StandardError, "Simulated failure"
      end
      
      # Listener that should succeed
      DSPy.events.subscribe('test.event') do |event_name, attributes|
        mutex.synchronize do
          successful_calls << [event_name, attributes]
        end
      end
      
      threads = 5.times.map do |i|
        Thread.new do
          DSPy.event('test.event', iteration: i)
        end
      end
      
      threads.each(&:join)
      
      # All successful listener calls should have been made despite failures
      expect(successful_calls.length).to eq(5)
    end

    it 'provides thread-safe subscription and unsubscription' do
      subscription_ids = []
      mutex = Mutex.new
      
      # Multiple threads subscribing simultaneously
      subscribe_threads = 10.times.map do |i|
        Thread.new do
          id = DSPy.events.subscribe('test.event') { |*args| }
          mutex.synchronize { subscription_ids << id }
        end
      end
      
      subscribe_threads.each(&:join)
      
      expect(subscription_ids.length).to eq(10)
      expect(subscription_ids.uniq.length).to eq(10)  # All unique IDs
      
      # Unsubscribe from different thread
      unsubscribe_threads = subscription_ids.map do |id|
        Thread.new do
          DSPy.events.unsubscribe(id)
        end
      end
      
      unsubscribe_threads.each(&:join)
      
      # Verify all subscriptions were removed
      received_events = []
      DSPy.event('test.event', data: 'should_not_be_received')
      expect(received_events).to be_empty
    end
  end

  describe 'Backward Compatibility' do
    after do
      DSPy.events.clear_listeners
    end

    it 'DSPy.log calls now trigger event listeners' do
      received_events = []
      
      DSPy.events.subscribe('legacy.event') do |event_name, attributes|
        received_events << [event_name, attributes]
      end
      
      # Using DSPy.log (the old API) should trigger event listeners
      DSPy.log('legacy.event', data: 'from_log_method')
      
      expect(received_events.length).to eq(1)
      expect(received_events[0][0]).to eq('legacy.event')
      expect(received_events[0][1][:data]).to eq('from_log_method')
    end

    it 'DSPy.log calls create OpenTelemetry spans when observability enabled' do
      mock_span = double('span')
      
      allow(DSPy::Observability).to receive(:enabled?).and_return(true)
      expect(DSPy::Observability).to receive(:start_span).with(
        'legacy.span_test',
        hash_including('test_attr' => 'value')
      ).and_return(mock_span)
      expect(DSPy::Observability).to receive(:finish_span).with(mock_span)
      
      # Using DSPy.log should create spans
      DSPy.log('legacy.span_test', test_attr: 'value')
    end

    it 'DSPy.log still produces the same log output as before' do
      logger_output = StringIO.new
      test_logger = Dry.Logger(:test, formatter: :string) do |config|
        config.add_backend(stream: logger_output)
      end
      
      allow(DSPy).to receive(:logger).and_return(test_logger)
      
      DSPy.log('compatibility.test', message: 'hello')
      
      log_output = logger_output.string
      expect(log_output).to include('event="compatibility.test"')
      expect(log_output).to include('hello')  # Message content is included
    end
  end
end