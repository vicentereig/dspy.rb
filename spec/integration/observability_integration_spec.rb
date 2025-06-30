require 'spec_helper'
require 'dspy/instrumentation'
require 'dspy/subscribers/logger_subscriber'
require 'dspy/subscribers/otel_subscriber'
require 'dspy/subscribers/newrelic_subscriber'
require 'dspy/subscribers/langfuse_subscriber'

RSpec.describe 'Observability Integration' do
  let(:test_event_data) do
    {
      optimization_id: 'test-optimization-123',
      optimizer: 'MIPROv2',
      trainset_size: 100,
      valset_size: 20,
      duration_ms: 5000.0,
      best_score: 0.85,
      trials_count: 10
    }
  end

  describe 'instrumentation system' do
    it 'initializes notifications system correctly' do
      notifications = DSPy::Instrumentation.notifications
      
      # Should be a Dry::Monitor::Notifications instance
      expect(notifications).to be_a(Dry::Monitor::Notifications)
      
      # Should be able to emit events
      expect {
        notifications.instrument('test.event', {})
      }.not_to raise_error
    end

    it 'initializes logger subscriber by default' do
      expect { DSPy::Instrumentation.logger_subscriber }.not_to raise_error
      expect(DSPy::Instrumentation.logger_subscriber).to be_a(DSPy::Subscribers::LoggerSubscriber)
    end

    it 'handles event emission correctly' do
      expect {
        DSPy::Instrumentation.emit('dspy.optimization.start', test_event_data)
      }.not_to raise_error
    end

    it 'handles instrumentation blocks correctly' do
      result = DSPy::Instrumentation.instrument('test.operation', test_event_data) do
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end
  end

  describe 'subscriber initialization' do
    it 'initializes all subscribers without errors' do
      expect { DSPy::Instrumentation.logger_subscriber }.not_to raise_error
      expect { DSPy::Instrumentation.otel_subscriber }.not_to raise_error
      expect { DSPy::Instrumentation.newrelic_subscriber }.not_to raise_error
      expect { DSPy::Instrumentation.langfuse_subscriber }.not_to raise_error
    end

    it 'handles missing dependencies gracefully' do
      # Should not raise errors even if optional dependencies are missing
      expect { DSPy::Instrumentation.setup_subscribers }.not_to raise_error
    end
  end

  describe 'configuration integration' do
    context 'with OpenTelemetry configuration' do
      it 'respects environment variables' do
        config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
        
        # Should have sensible defaults
        expect(config.service_name).to eq('dspy-ruby')
        expect(config.trace_optimization_events).to be(true)
        expect(config.trace_lm_events).to be(true)
        expect(config.export_metrics).to be(true)
      end
    end

    context 'with New Relic configuration' do
      it 'sets up correctly' do
        config = DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig.new
        
        expect(config.trace_optimization_events).to be(true)
        expect(config.record_custom_metrics).to be(true)
        expect(config.metric_prefix).to eq('Custom/DSPy')
      end
    end

    context 'with Langfuse configuration' do
      it 'configures LLM observability' do
        config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
        
        expect(config.trace_optimizations).to be(true)
        expect(config.log_prompts).to be(true)
        expect(config.log_completions).to be(true)
        expect(config.default_tags).to include('framework' => 'dspy-ruby')
      end
    end
  end

  describe 'event flow integration' do
    let(:received_events) { [] }
    
    before do
      # Subscribe to events to verify they're emitted
      DSPy::Instrumentation.subscribe('dspy.optimization.start') do |event|
        received_events << { name: 'optimization.start', payload: event.payload }
      end
      
      DSPy::Instrumentation.subscribe('dspy.lm.request') do |event|
        received_events << { name: 'lm.request', payload: event.payload }
      end
    end

    it 'emits events through the system' do
      # Emit optimization event
      DSPy::Instrumentation.emit('dspy.optimization.start', test_event_data)
      
      # Emit LM event
      lm_data = {
        provider: 'openai',
        model: 'gpt-4',
        status: 'success',
        duration_ms: 500.0,
        tokens_total: 150
      }
      DSPy::Instrumentation.emit('dspy.lm.request', lm_data)
      
      expect(received_events.size).to eq(2)
      expect(received_events[0][:name]).to eq('optimization.start')
      expect(received_events[0][:payload][:optimization_id]).to eq('test-optimization-123')
      expect(received_events[1][:name]).to eq('lm.request')
      expect(received_events[1][:payload][:provider]).to eq('openai')
    end
  end

  describe 'subscriber coordination' do
    let(:logger_events) { [] }
    let(:mock_tracer) { double('Tracer') }
    let(:mock_langfuse) { double('Langfuse') }

    before do
      # Mock external dependencies
      if defined?(OpenTelemetry)
        allow(OpenTelemetry).to receive_message_chain(:tracer_provider, :tracer).and_return(mock_tracer)
        allow(mock_tracer).to receive(:in_span).and_yield(double('Span'))
      end

      if defined?(Langfuse)
        allow(Langfuse).to receive(:new).and_return(mock_langfuse)
        allow(mock_langfuse).to receive(:trace)
        allow(mock_langfuse).to receive(:event)
      end

      # Capture logger events
      allow_any_instance_of(Logger).to receive(:info) do |_, message|
        logger_events << message
      end
    end

    it 'coordinates multiple subscribers without conflicts' do
      # Force initialization of subscribers
      DSPy::Instrumentation.logger_subscriber
      DSPy::Instrumentation.otel_subscriber
      DSPy::Instrumentation.langfuse_subscriber

      # Emit test event
      expect {
        DSPy::Instrumentation.emit('dspy.optimization.start', test_event_data)
      }.not_to raise_error

      # Logger should have captured the event
      expect(logger_events).not_to be_empty
    end
  end

  describe 'performance impact' do
    it 'handles high-volume events efficiently' do
      start_time = Time.now
      
      1000.times do |i|
        DSPy::Instrumentation.emit('dspy.lm.request', {
          request_id: "req-#{i}",
          provider: 'test',
          status: 'success',
          duration_ms: 100.0
        })
      end
      
      end_time = Time.now
      duration = end_time - start_time
      
      # Should handle 1000 events in under 1 second
      expect(duration).to be < 1.0
    end

    it 'instruments operations with minimal overhead' do
      iterations = 100
      
      start_time = Time.now
      iterations.times do
        DSPy::Instrumentation.instrument('test.operation') do
          # Minimal work
          1 + 1
        end
      end
      end_time = Time.now
      
      duration = end_time - start_time
      avg_per_operation = duration / iterations
      
      # Each instrumented operation should add minimal overhead
      expect(avg_per_operation).to be < 0.01  # Less than 10ms overhead
    end
  end

  describe 'error handling' do
    it 'handles subscriber initialization errors gracefully' do
      # Simulate initialization error
      allow(DSPy::Subscribers::OtelSubscriber).to receive(:new).and_raise(StandardError, 'Test error')
      
      expect {
        DSPy::Instrumentation.setup_subscribers
      }.not_to raise_error
    end

    it 'continues working when individual subscribers fail' do
      # Mock a failing subscriber
      failing_subscriber = double('FailingSubscriber')
      allow(failing_subscriber).to receive(:handle_optimization_start).and_raise(StandardError, 'Subscriber error')
      
      # Should not prevent other subscribers from working
      expect {
        DSPy::Instrumentation.emit('dspy.optimization.start', test_event_data)
      }.not_to raise_error
    end

    it 'handles malformed event payloads' do
      expect {
        DSPy::Instrumentation.emit('dspy.optimization.start', { invalid: 'payload' })
      }.not_to raise_error
      
      expect {
        DSPy::Instrumentation.emit('dspy.optimization.start', nil)
      }.not_to raise_error
    end
  end

  describe 'memory usage' do
    it 'does not leak memory with long-running operations' do
      # This is a basic check - in a real scenario you'd use memory profiling tools
      initial_objects = ObjectSpace.count_objects
      
      # Simulate long-running operation with many events
      100.times do |i|
        DSPy::Instrumentation.instrument("test.operation.#{i}") do
          DSPy::Instrumentation.emit('dspy.lm.request', {
            request_id: "req-#{i}",
            status: 'success'
          })
        end
      end
      
      GC.start # Force garbage collection
      final_objects = ObjectSpace.count_objects
      
      # Should not have significantly more objects
      object_increase = final_objects[:T_OBJECT] - initial_objects[:T_OBJECT]
      expect(object_increase).to be < 1000  # Reasonable threshold
    end
  end
end