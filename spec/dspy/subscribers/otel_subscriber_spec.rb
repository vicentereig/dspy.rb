require 'spec_helper'
require 'dspy/subscribers/otel_subscriber'

RSpec.describe DSPy::Subscribers::OtelSubscriber do
  let(:config) do
    config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
    config.enabled = false # Disable by default for testing
    config
  end
  let(:subscriber) { DSPy::Subscribers::OtelSubscriber.new(config: config) }

  describe DSPy::Subscribers::OtelSubscriber::OtelConfig do
    describe '#initialize' do
      it 'sets default configuration values' do
        config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
        
        expect(config.service_name).to eq('dspy-ruby')
        expect(config.trace_optimization_events).to be(true)
        expect(config.trace_lm_events).to be(true)
        expect(config.export_metrics).to be(true)
        expect(config.sample_rate).to eq(1.0)
      end

      it 'respects environment variables' do
        # Create a mock ENV object that returns specific values
        mock_env = ENV.to_h.merge({
          'OTEL_SERVICE_NAME' => 'test-service',
          'OTEL_SERVICE_VERSION' => '2.0.0',
          'OTEL_EXPORTER_OTLP_ENDPOINT' => 'http://localhost:4318',
          'OTEL_EXPORTER_OTLP_HEADERS' => 'api-key=test123,x-custom=value',
          'OTEL_TRACE_SAMPLE_RATE' => '0.5'
        })
        
        stub_const('ENV', mock_env)

        config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
        
        expect(config.service_name).to eq('test-service')
        expect(config.service_version).to eq('2.0.0')
        expect(config.endpoint).to eq('http://localhost:4318')
        expect(config.headers).to eq({'api-key' => 'test123', 'x-custom' => 'value'})
        expect(config.sample_rate).to eq(0.5)
      end
    end
  end

  describe '#initialize' do
    it 'creates subscriber with default config' do
      subscriber = DSPy::Subscribers::OtelSubscriber.new
      
      expect(subscriber.config).to be_a(DSPy::Subscribers::OtelSubscriber::OtelConfig)
    end

    it 'creates subscriber with custom config' do
      custom_config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
      custom_config.service_name = 'custom-service'
      
      subscriber = DSPy::Subscribers::OtelSubscriber.new(config: custom_config)
      
      expect(subscriber.config.service_name).to eq('custom-service')
    end
  end

  context 'when OpenTelemetry is available' do
    let(:mock_tracer) { double('Tracer') }
    let(:mock_meter) { double('Meter') }
    let(:mock_span) { double('Span') }
    let(:mock_counter) { double('Counter') }
    let(:mock_histogram) { double('Histogram') }

    before do
      # Create a module that behaves like OpenTelemetry  
      opentelemetry_module = Module.new
      sdk_module = Module.new
      trace_module = Module.new
      status_module = Module.new
      tracer_provider_mock = double('TracerProvider')
      meter_provider_mock = double('MeterProvider')
      
      allow(opentelemetry_module).to receive(:tracer_provider).and_return(tracer_provider_mock)
      allow(opentelemetry_module).to receive(:meter_provider).and_return(meter_provider_mock)
      allow(tracer_provider_mock).to receive(:tracer).and_return(mock_tracer)
      allow(meter_provider_mock).to receive(:meter).and_return(mock_meter)
      
      # Mock SDK configuration
      allow(sdk_module).to receive(:configure).and_yield(double('Config', 
        :service_name= => nil, 
        :service_version= => nil, 
        :add_span_processor => nil
      ))
      
      # Mock Trace::Status
      allow(status_module).to receive(:error).and_return(double('Status'))
      
      stub_const('OpenTelemetry', opentelemetry_module)
      stub_const('OpenTelemetry::SDK', sdk_module)
      stub_const('OpenTelemetry::Trace', trace_module)
      stub_const('OpenTelemetry::Trace::Status', status_module)
      
      config.enabled = true
    end

    after do
      # Clear notifications to remove event handlers containing RSpec doubles
      DSPy::Instrumentation.instance_variable_set(:@notifications, nil)
    end



    describe 'optimization event handling' do
      it 'handles optimization start events' do
        expect(mock_tracer).to receive(:start_span).with(
          'dspy.optimization',
          hash_including(attributes: hash_including('dspy.operation' => 'optimization'))
        ).and_return(mock_span)

        expect(mock_meter).to receive(:create_counter).with(
          'dspy.optimization.started',
          description: 'Number of optimizations started'
        ).and_return(mock_counter)
        expect(mock_counter).to receive(:add).with(1, hash_including(attributes: hash_including('optimizer' => 'MIPROv2')))

        event = double('Event', payload: {
          optimization_id: 'test-123',
          optimizer: 'MIPROv2',
          trainset_size: 100,
          valset_size: 20
        })

        subscriber.send(:handle_optimization_start, event)
      end

      it 'handles optimization complete events' do
        # Setup span from start event
        optimization_id = 'test-123'
        subscriber.instance_variable_get(:@optimization_spans)[optimization_id] = mock_span

        expect(mock_span).to receive(:set_attribute).with('dspy.optimization.status', 'success')
        expect(mock_span).to receive(:set_attribute).with('dspy.optimization.duration_ms', 5000.0)
        expect(mock_span).to receive(:set_attribute).with('dspy.optimization.best_score', 0.85)
        expect(mock_span).to receive(:set_attribute).with('dspy.optimization.trials_count', 10)
        expect(mock_span).to receive(:set_attribute).with('dspy.optimization.final_instruction', nil)
        expect(mock_span).to receive(:finish)

        expect(mock_meter).to receive(:create_histogram).with(
          'dspy.optimization.duration',
          description: 'Optimization duration in milliseconds'
        ).and_return(mock_histogram)
        expect(mock_histogram).to receive(:record).with(5000.0, hash_including(attributes: hash_including('optimizer' => 'MIPROv2')))

        expect(mock_meter).to receive(:create_histogram).with(
          'dspy.optimization.score',
          description: 'Best optimization score achieved'
        ).and_return(mock_histogram)
        expect(mock_histogram).to receive(:record).with(0.85, hash_including(attributes: hash_including('optimizer' => 'MIPROv2')))

        event = double('Event', payload: {
          optimization_id: optimization_id,
          optimizer: 'MIPROv2',
          duration_ms: 5000.0,
          best_score: 0.85,
          trials_count: 10
        })

        subscriber.send(:handle_optimization_complete, event)
      end

      it 'handles trial start events' do
        expect(mock_tracer).to receive(:start_span).with(
          'dspy.optimization.trial',
          hash_including(attributes: hash_including('dspy.operation' => 'optimization_trial'))
        ).and_return(mock_span)

        event = double('Event', payload: {
          optimization_id: 'test-123',
          trial_number: 1,
          instruction: 'Test instruction',
          examples_count: 5
        })

        subscriber.send(:handle_trial_start, event)
      end

      it 'handles trial complete events' do
        # Setup span from trial start
        trial_id = 'test-123_1'
        subscriber.instance_variable_get(:@trial_spans)[trial_id] = mock_span

        expect(mock_span).to receive(:set_attribute).with('dspy.trial.status', 'success')
        expect(mock_span).to receive(:set_attribute).with('dspy.trial.duration_ms', 1000.0)
        expect(mock_span).to receive(:set_attribute).with('dspy.trial.score', 0.75)
        expect(mock_span).to receive(:finish)

        event = double('Event', payload: {
          optimization_id: 'test-123',
          trial_number: 1,
          status: 'success',
          duration_ms: 1000.0,
          score: 0.75
        })

        subscriber.send(:handle_trial_complete, event)
      end

      it 'handles optimization errors' do
        # Setup span from start event
        optimization_id = 'test-123'
        subscriber.instance_variable_get(:@optimization_spans)[optimization_id] = mock_span

        expect(mock_span).to receive(:set_attribute).with('dspy.optimization.status', 'error')
        expect(mock_span).to receive(:set_attribute).with('dspy.optimization.error', 'Test error')
        expect(mock_span).to receive(:record_exception).with('Test error')
        expect(mock_span).to receive(:status=)
        expect(mock_span).to receive(:finish)

        expect(mock_meter).to receive(:create_counter).with(
          'dspy.optimization.errors',
          description: 'Number of optimization errors'
        ).and_return(mock_counter)
        expect(mock_counter).to receive(:add).with(1, hash_including(attributes: hash_including('optimizer' => 'MIPROv2')))

        event = double('Event', payload: {
          optimization_id: optimization_id,
          optimizer: 'MIPROv2',
          error_message: 'Test error',
          error_type: 'StandardError'
        })

        subscriber.send(:handle_optimization_error, event)
      end
    end

    describe 'LM event handling' do
      it 'handles LM request events' do
        expect(mock_tracer).to receive(:in_span).with(
          'dspy.lm.request',
          hash_including(attributes: hash_including('dspy.operation' => 'lm_request'))
        ).and_yield(mock_span)

        expect(mock_meter).to receive(:create_histogram).with(
          'dspy.lm.request.duration',
          description: 'LM request duration in milliseconds'
        ).and_return(mock_histogram)
        expect(mock_histogram).to receive(:record).with(500.0, hash_including(attributes: hash_including('provider' => 'openai')))

        expect(mock_meter).to receive(:create_histogram).with(
          'dspy.lm.tokens.total',
          description: 'Total tokens used in LM request'
        ).and_return(mock_histogram)
        expect(mock_histogram).to receive(:record).with(150, hash_including(attributes: hash_including('provider' => 'openai')))

        expect(mock_meter).to receive(:create_histogram).with(
          'dspy.lm.cost',
          description: 'Cost of LM request'
        ).and_return(mock_histogram)
        expect(mock_histogram).to receive(:record).with(0.005, hash_including(attributes: hash_including('provider' => 'openai')))

        event = double('Event', payload: {
          provider: 'openai',
          model: 'gpt-4',
          status: 'success',
          duration_ms: 500.0,
          tokens_total: 150,
          tokens_input: 100,
          tokens_output: 50,
          cost: 0.005
        })

        subscriber.send(:handle_lm_request, event)
      end

      it 'handles prediction events' do
        expect(mock_tracer).to receive(:in_span).with(
          'dspy.predict',
          hash_including(attributes: hash_including('dspy.operation' => 'predict'))
        ).and_yield(mock_span)

        event = double('Event', payload: {
          signature_class: 'TestSignature',
          status: 'success',
          duration_ms: 200.0,
          input_size: 50
        })

        subscriber.send(:handle_prediction, event)
      end
    end
  end

  context 'when OpenTelemetry is not available' do
    before do
      config.enabled = false
    end

    it 'does not set up OpenTelemetry' do
      expect { subscriber }.not_to raise_error
    end

    it 'handles events gracefully without OpenTelemetry' do
      event = double('Event', payload: { optimization_id: 'test-123' })
      
      expect { subscriber.send(:handle_optimization_start, event) }.not_to raise_error
      expect { subscriber.send(:handle_lm_request, event) }.not_to raise_error
    end
  end

  describe 'event subscription' do
    it 'subscribes to optimization events when enabled' do
      # Setup OpenTelemetry mocking for this test
      opentelemetry_module = Module.new
      sdk_module = Module.new
      trace_module = Module.new
      status_module = Module.new
      tracer_provider_mock = double('TracerProvider')
      meter_provider_mock = double('MeterProvider')
      test_tracer = double('Tracer')
      test_meter = double('Meter')
      
      allow(opentelemetry_module).to receive(:tracer_provider).and_return(tracer_provider_mock)
      allow(opentelemetry_module).to receive(:meter_provider).and_return(meter_provider_mock)
      allow(tracer_provider_mock).to receive(:tracer).and_return(test_tracer)
      allow(meter_provider_mock).to receive(:meter).and_return(test_meter)
      
      allow(sdk_module).to receive(:configure).and_yield(double('Config', 
        :service_name= => nil, 
        :service_version= => nil, 
        :add_span_processor => nil
      ))
      
      allow(status_module).to receive(:error).and_return(double('Status'))
      
      stub_const('OpenTelemetry', opentelemetry_module)
      stub_const('OpenTelemetry::SDK', sdk_module)
      stub_const('OpenTelemetry::Trace', trace_module)
      stub_const('OpenTelemetry::Trace::Status', status_module)
      
      test_config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
      test_config.enabled = true
      test_config.trace_optimization_events = true
      
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.start')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.complete')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.trial_start')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.trial_complete')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.bootstrap_start')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.bootstrap_complete')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.error')

      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.lm.request')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.predict')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.chain_of_thought')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.save_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.load_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.register_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.deploy_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.rollback_start')

      DSPy::Subscribers::OtelSubscriber.new(config: test_config)
    end

    it 'subscribes to LM events when enabled' do
      # Setup OpenTelemetry mocking for this test
      opentelemetry_module = Module.new
      sdk_module = Module.new
      trace_module = Module.new
      status_module = Module.new
      tracer_provider_mock = double('TracerProvider')
      meter_provider_mock = double('MeterProvider')
      test_tracer = double('Tracer')
      test_meter = double('Meter')
      
      allow(opentelemetry_module).to receive(:tracer_provider).and_return(tracer_provider_mock)
      allow(opentelemetry_module).to receive(:meter_provider).and_return(meter_provider_mock)
      allow(tracer_provider_mock).to receive(:tracer).and_return(test_tracer)
      allow(meter_provider_mock).to receive(:meter).and_return(test_meter)
      
      allow(sdk_module).to receive(:configure).and_yield(double('Config', 
        :service_name= => nil, 
        :service_version= => nil, 
        :add_span_processor => nil
      ))
      
      allow(status_module).to receive(:error).and_return(double('Status'))
      
      stub_const('OpenTelemetry', opentelemetry_module)
      stub_const('OpenTelemetry::SDK', sdk_module)
      stub_const('OpenTelemetry::Trace', trace_module)
      stub_const('OpenTelemetry::Trace::Status', status_module)
      
      test_config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
      test_config.enabled = true
      test_config.trace_lm_events = true
      
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.lm.request')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.predict')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.chain_of_thought')

      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.trial_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.trial_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.bootstrap_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.bootstrap_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.error')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.save_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.load_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.register_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.deploy_start')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.rollback_start')

      DSPy::Subscribers::OtelSubscriber.new(config: test_config)
    end

    it 'does not subscribe when disabled' do
      config.enabled = false
      
      expect(DSPy::Instrumentation).not_to receive(:subscribe)
      
      DSPy::Subscribers::OtelSubscriber.new(config: config)
    end
  end
end