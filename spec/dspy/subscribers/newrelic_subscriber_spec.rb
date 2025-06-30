require 'spec_helper'
require 'dspy/subscribers/newrelic_subscriber'

RSpec.describe DSPy::Subscribers::NewrelicSubscriber do
  let(:config) do
    config = DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig.new
    config.enabled = false # Disable by default for testing
    config
  end
  let(:subscriber) { DSPy::Subscribers::NewrelicSubscriber.new(config: config) }

  describe DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig do
    describe '#initialize' do
      it 'sets default configuration values' do
        config = DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig.new
        
        expect(config.app_name).to eq('DSPy Ruby Application')
        expect(config.trace_optimization_events).to be(true)
        expect(config.trace_lm_events).to be(true)
        expect(config.record_custom_metrics).to be(true)
        expect(config.record_custom_events).to be(true)
        expect(config.metric_prefix).to eq('Custom/DSPy')
      end
    end
  end

  describe '#initialize' do
    it 'creates subscriber with default config' do
      subscriber = DSPy::Subscribers::NewrelicSubscriber.new
      
      expect(subscriber.config).to be_a(DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig)
    end

    it 'creates subscriber with custom config' do
      custom_config = DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig.new
      custom_config.app_name = 'Custom App'
      
      subscriber = DSPy::Subscribers::NewrelicSubscriber.new(config: custom_config)
      
      expect(subscriber.config.app_name).to eq('Custom App')
    end
  end

  context 'when New Relic is available' do
    before do
      stub_const('NewRelic', double('NewRelic'))
      stub_const('NewRelic::Agent', double('Agent'))
      
      config.enabled = true
    end

    describe 'optimization event handling' do
      it 'handles optimization start events' do
        expect(NewRelic::Agent).to receive(:start_transaction).with(
          name: 'DSPy/Optimization',
          category: :task,
          options: hash_including(custom_params: hash_including(optimization_id: 'test-123'))
        )

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyOptimizationStart',
          hash_including(optimization_id: 'test-123', optimizer: 'MIPROv2')
        )

        event = double('Event', payload: {
          optimization_id: 'test-123',
          optimizer: 'MIPROv2',
          trainset_size: 100,
          valset_size: 20
        })

        subscriber.send(:handle_optimization_start, event)
      end

      it 'handles optimization complete events' do
        # Setup transaction info from start event
        optimization_id = 'test-123'
        subscriber.instance_variable_get(:@optimization_transactions)[optimization_id] = {
          started_at: Time.now,
          optimizer: 'MIPROv2'
        }

        expect(NewRelic::Agent).to receive(:add_custom_attributes).with(hash_including(
          'dspy.optimization.status' => 'success',
          'dspy.optimization.duration_ms' => 5000.0,
          'dspy.optimization.best_score' => 0.85
        ))

        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Optimization/Duration', 5000.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Optimization/BestScore', 0.85)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Optimization/TrialsCount', 10)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Optimization/Completed/MIPROv2', 1)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyOptimizationComplete',
          hash_including(optimization_id: optimization_id, optimizer: 'MIPROv2', status: 'success')
        )

        expect(NewRelic::Agent).to receive(:end_transaction)

        event = double('Event', payload: {
          optimization_id: optimization_id,
          duration_ms: 5000.0,
          best_score: 0.85,
          trials_count: 10
        })

        subscriber.send(:handle_optimization_complete, event)
      end

      it 'handles trial start events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Trial/Started', 1)

        event = double('Event', payload: {
          optimization_id: 'test-123',
          trial_number: 1,
          instruction: 'Test instruction'
        })

        subscriber.send(:handle_trial_start, event)
      end

      it 'handles trial complete events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Trial/Completed', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Trial/Duration', 1000.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Trial/Score', 0.75)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyTrialComplete',
          hash_including(trial_number: 1, score: 0.75, status: 'success')
        )

        event = double('Event', payload: {
          optimization_id: 'test-123',
          trial_number: 1,
          duration_ms: 1000.0,
          score: 0.75,
          status: 'success',
          instruction: 'Test instruction'
        })

        subscriber.send(:handle_trial_complete, event)
      end

      it 'handles trial errors' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Trial/Completed', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Trial/Duration', 1000.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Trial/Errors', 1)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyTrialComplete',
          hash_including(trial_number: 1, status: 'error')
        )

        event = double('Event', payload: {
          optimization_id: 'test-123',
          trial_number: 1,
          duration_ms: 1000.0,
          status: 'error',
          error_message: 'Test error'
        })

        subscriber.send(:handle_trial_complete, event)
      end

      it 'handles optimization errors' do
        # Setup transaction info
        optimization_id = 'test-123'
        subscriber.instance_variable_get(:@optimization_transactions)[optimization_id] = {
          started_at: Time.now,
          optimizer: 'MIPROv2'
        }

        expect(NewRelic::Agent).to receive(:notice_error).with(
          instance_of(StandardError),
          hash_including(optimization_id: optimization_id, optimizer: 'MIPROv2')
        )

        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Optimization/Errors', 1)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyOptimizationError',
          hash_including(optimization_id: optimization_id, error_message: 'Test error')
        )

        expect(NewRelic::Agent).to receive(:add_custom_attributes).with(hash_including(
          'dspy.optimization.status' => 'error',
          'dspy.optimization.error' => 'Test error'
        ))

        expect(NewRelic::Agent).to receive(:end_transaction)

        event = double('Event', payload: {
          optimization_id: optimization_id,
          optimizer: 'MIPROv2',
          error_message: 'Test error',
          error_type: 'StandardError'
        })

        subscriber.send(:handle_optimization_error, event)
      end

      it 'handles bootstrap events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Bootstrap/Started', 1)

        start_event = double('Event', payload: {
          target_count: 10,
          trainset_size: 100
        })

        subscriber.send(:handle_bootstrap_start, start_event)

        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Bootstrap/Completed', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Bootstrap/Duration', 2000.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Bootstrap/ExamplesGenerated', 8)

        complete_event = double('Event', payload: {
          duration_ms: 2000.0,
          examples_generated: 8
        })

        subscriber.send(:handle_bootstrap_complete, complete_event)
      end
    end

    describe 'LM event handling' do
      it 'handles LM request events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Requests', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Duration', 500.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Tokens/Total', 150)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Tokens/Input', 100)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Tokens/Output', 50)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Cost', 0.005)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyLMRequest',
          hash_including(provider: 'openai', model: 'gpt-4', status: 'success')
        )

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

      it 'handles LM request errors' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Requests', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Duration', 1000.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/LM/Errors', 1)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyLMRequest',
          hash_including(provider: 'openai', status: 'error', error_message: 'API Error')
        )

        event = double('Event', payload: {
          provider: 'openai',
          model: 'gpt-4',
          status: 'error',
          duration_ms: 1000.0,
          error_message: 'API Error'
        })

        subscriber.send(:handle_lm_request, event)
      end

      it 'handles prediction events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Predict/Requests', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Predict/Duration', 200.0)

        event = double('Event', payload: {
          signature_class: 'TestSignature',
          status: 'success',
          duration_ms: 200.0
        })

        subscriber.send(:handle_prediction, event)
      end

      it 'handles chain of thought events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/ChainOfThought/Requests', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/ChainOfThought/Duration', 800.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/ChainOfThought/ReasoningSteps', 3)

        event = double('Event', payload: {
          signature_class: 'ReasoningSignature',
          status: 'success',
          duration_ms: 800.0,
          reasoning_steps: 3
        })

        subscriber.send(:handle_chain_of_thought, event)
      end
    end

    describe 'storage and registry event handling' do
      it 'handles storage operations' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Storage/Save', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Storage/Duration', 100.0)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Storage/SizeBytes', 1024)

        event = double('Event', payload: {
          program_id: 'test-program-123',
          duration_ms: 100.0,
          size_bytes: 1024
        })

        subscriber.send(:handle_storage_operation, event, 'save')
      end

      it 'handles registry operations' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Registry/Register', 1)
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Registry/Duration', 50.0)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyRegistryRegister',
          hash_including(signature_name: 'TestSignature', version: 'v1.0.0')
        )

        event = double('Event', payload: {
          signature_name: 'TestSignature',
          version: 'v1.0.0',
          duration_ms: 50.0,
          performance_score: 0.85
        })

        subscriber.send(:handle_registry_operation, event, 'register')
      end

      it 'handles auto deployment events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Registry/AutoDeployments', 1)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyAutoDeployment',
          hash_including(signature_name: 'TestSignature', version: 'v2.0.0')
        )

        event = double('Event', payload: {
          signature_name: 'TestSignature',
          version: 'v2.0.0'
        })

        subscriber.send(:handle_auto_deployment, event)
      end

      it 'handles automatic rollback events' do
        expect(NewRelic::Agent).to receive(:record_metric).with('Custom/DSPy/Registry/AutoRollbacks', 1)

        expect(NewRelic::Agent).to receive(:record_custom_event).with(
          'DSPyAutoRollback',
          hash_including(
            signature_name: 'TestSignature',
            current_score: 0.6,
            previous_score: 0.8,
            performance_drop: 0.2
          )
        )

        event = double('Event', payload: {
          signature_name: 'TestSignature',
          current_score: 0.6,
          previous_score: 0.8,
          performance_drop: 0.2
        })

        subscriber.send(:handle_automatic_rollback, event)
      end
    end
  end

  context 'when New Relic is not available' do
    before do
      config.enabled = false
    end

    it 'does not set up New Relic' do
      expect { subscriber }.not_to raise_error
    end

    it 'handles events gracefully without New Relic' do
      event = double('Event', payload: { optimization_id: 'test-123' })
      
      expect { subscriber.send(:handle_optimization_start, event) }.not_to raise_error
      expect { subscriber.send(:handle_lm_request, event) }.not_to raise_error
    end
  end

  describe 'event subscription' do
    it 'subscribes to optimization events when enabled' do
      config.enabled = true
      config.trace_optimization_events = true
      
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
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.save_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.load_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.register_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.deploy_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.rollback_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.auto_deployment')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.automatic_rollback')

      DSPy::Subscribers::NewrelicSubscriber.new(config: config)
    end

    it 'subscribes to LM events when enabled' do
      config.enabled = true
      config.trace_lm_events = true
      
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
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.save_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.storage.load_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.register_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.deploy_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.rollback_complete')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.auto_deployment')
      allow(DSPy::Instrumentation).to receive(:subscribe).with('dspy.registry.automatic_rollback')

      DSPy::Subscribers::NewrelicSubscriber.new(config: config)
    end

    it 'does not subscribe when disabled' do
      config.enabled = false
      
      expect(DSPy::Instrumentation).not_to receive(:subscribe)
      
      DSPy::Subscribers::NewrelicSubscriber.new(config: config)
    end
  end

  describe 'configuration options' do
    it 'respects custom metrics disabled' do
      config.enabled = true
      config.record_custom_metrics = false
      
      # Mock New Relic
      stub_const('NewRelic', double('NewRelic'))
      stub_const('NewRelic::Agent', double('Agent'))
      
      expect(NewRelic::Agent).not_to receive(:record_metric)
      expect(NewRelic::Agent).to receive(:record_custom_event) # Events should still work

      event = double('Event', payload: {
        provider: 'openai',
        model: 'gpt-4',
        status: 'success',
        duration_ms: 500.0
      })

      subscriber_with_config = DSPy::Subscribers::NewrelicSubscriber.new(config: config)
      subscriber_with_config.send(:handle_lm_request, event)
    end

    it 'respects custom events disabled' do
      config.enabled = true
      config.record_custom_events = false
      
      # Mock New Relic
      stub_const('NewRelic', double('NewRelic'))
      stub_const('NewRelic::Agent', double('Agent'))
      
      expect(NewRelic::Agent).to receive(:record_metric).at_least(:once) # Metrics should still work
      expect(NewRelic::Agent).not_to receive(:record_custom_event)

      event = double('Event', payload: {
        provider: 'openai',
        model: 'gpt-4',
        status: 'success',
        duration_ms: 500.0
      })

      subscriber_with_config = DSPy::Subscribers::NewrelicSubscriber.new(config: config)
      subscriber_with_config.send(:handle_lm_request, event)
    end
  end
end