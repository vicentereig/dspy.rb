require 'spec_helper'
require 'dspy/subscribers/langfuse_subscriber'

RSpec.describe DSPy::Subscribers::LangfuseSubscriber do
  let(:config) do
    config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
    config.enabled = false # Disable by default for testing
    config
  end
  let(:subscriber) { DSPy::Subscribers::LangfuseSubscriber.new(config: config) }

  describe DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig do
    describe '#initialize' do
      it 'sets default configuration values' do
        config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
        
        expect(config.host).to eq('https://cloud.langfuse.com')
        expect(config.trace_optimizations).to be(true)
        expect(config.trace_lm_calls).to be(true)
        expect(config.trace_evaluations).to be(true)
        expect(config.log_prompts).to be(true)
        expect(config.log_completions).to be(true)
        expect(config.calculate_costs).to be(true)
        expect(config.default_tags).to eq({ 'framework' => 'dspy-ruby' })
      end

      it 'respects environment variables' do
        allow(ENV).to receive(:[]).with('LANGFUSE_PUBLIC_KEY').and_return('pk_test_123')
        allow(ENV).to receive(:[]).with('LANGFUSE_SECRET_KEY').and_return('sk_test_456')
        allow(ENV).to receive(:[]).with('LANGFUSE_HOST').and_return('https://custom.langfuse.com')
        allow(ENV).to receive(:[]).with(anything).and_call_original

        config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
        
        expect(config.public_key).to eq('pk_test_123')
        expect(config.secret_key).to eq('sk_test_456')
        expect(config.host).to eq('https://custom.langfuse.com')
      end
    end
  end

  describe '#initialize' do
    it 'creates subscriber with default config' do
      subscriber = DSPy::Subscribers::LangfuseSubscriber.new
      
      expect(subscriber.config).to be_a(DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig)
    end

    it 'creates subscriber with custom config' do
      custom_config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
      custom_config.host = 'https://custom.langfuse.com'
      
      subscriber = DSPy::Subscribers::LangfuseSubscriber.new(config: custom_config)
      
      expect(subscriber.config.host).to eq('https://custom.langfuse.com')
    end
  end

  context 'when Langfuse is available' do
    let(:mock_langfuse) { double('Langfuse') }
    let(:mock_trace) { double('Trace') }
    let(:mock_span) { double('Span') }
    let(:mock_generation) { double('Generation') }

    before do
      stub_const('Langfuse', double('Langfuse'))
      allow(Langfuse).to receive(:new).and_return(mock_langfuse)
      
      config.enabled = true
      config.secret_key = 'test_secret'
    end

    describe 'optimization event handling' do
      it 'handles optimization start events' do
        expect(mock_langfuse).to receive(:trace).with(
          hash_including(
            name: "DSPy Optimization",
            metadata: hash_including(:optimizer)
          )
        ).and_return(mock_trace)

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "optimization_started",
            metadata: hash_including(:optimizer)
          )
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
        # Setup trace from start event
        optimization_id = 'test-123'
        subscriber.instance_variable_get(:@optimization_traces)[optimization_id] = mock_trace

        expect(mock_trace).to receive(:update).with(
          hash_including(
            output: hash_including(:best_score),
            metadata: hash_including(:duration_ms)
          )
        )

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "optimization_completed",
            metadata: hash_including(:best_score)
          )
        )

        expect(mock_langfuse).to receive(:score).with(
          hash_including(
            name: "optimization_performance",
            value: 0.85
          )
        )

        event = double('Event', payload: {
          optimization_id: optimization_id,
          duration_ms: 5000.0,
          best_score: 0.85,
          trials_count: 10,
          final_instruction: 'Test instruction'
        })

        subscriber.send(:handle_optimization_complete, event)
      end

      it 'handles trial start events' do
        optimization_id = 'test-123'
        subscriber.instance_variable_get(:@optimization_traces)[optimization_id] = mock_trace

        expect(mock_langfuse).to receive(:span).with(
          hash_including(
            trace_id: optimization_id,
            name: "Optimization Trial",
            input: hash_including(:trial_number)
          )
        ).and_return(mock_span)

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "trial_started",
            metadata: hash_including(:trial_number)
          )
        )

        event = double('Event', payload: {
          optimization_id: optimization_id,
          trial_number: 1,
          instruction: 'Test instruction',
          examples_count: 5
        })

        subscriber.send(:handle_trial_start, event)
      end

      it 'handles trial complete events' do
        # Setup span from trial start
        optimization_id = 'test-123'
        trial_id = "#{optimization_id}_1"
        subscriber.instance_variable_get(:@trial_spans)[trial_id] = mock_span

        expect(mock_span).to receive(:update).with(
          hash_including(
            output: hash_including(:score),
            metadata: hash_including(:duration_ms)
          )
        )

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "trial_completed",
            metadata: hash_including(:score)
          )
        )

        expect(mock_langfuse).to receive(:score).with(
          hash_including(
            name: "trial_score",
            value: 0.75
          )
        )

        event = double('Event', payload: {
          optimization_id: optimization_id,
          trial_number: 1,
          status: 'success',
          duration_ms: 1000.0,
          score: 0.75
        })

        subscriber.send(:handle_trial_complete, event)
      end

      it 'handles optimization errors' do
        # Setup trace from start event
        optimization_id = 'test-123'
        subscriber.instance_variable_get(:@optimization_traces)[optimization_id] = mock_trace

        expect(mock_trace).to receive(:update).with(
          hash_including(
            output: hash_including(:error),
            metadata: hash_including(status: 'error')
          )
        )

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "optimization_error",
            metadata: hash_including(:error_message)
          )
        )

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
        expect(mock_langfuse).to receive(:generation).with(
          hash_including(
            name: "LM Request",
            model: 'gpt-4',
            metadata: hash_including(:provider)
          )
        ).and_return(mock_generation)

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "lm_request",
            metadata: hash_including(:provider)
          )
        )

        expect(mock_langfuse).to receive(:score).with(
          hash_including(
            name: "request_cost",
            value: 0.005
          )
        )

        event = double('Event', payload: {
          request_id: 'req-123',
          provider: 'openai',
          model: 'gpt-4',
          status: 'success',
          duration_ms: 500.0,
          tokens_total: 150,
          tokens_input: 100,
          tokens_output: 50,
          cost: 0.005,
          prompt: 'Test prompt',
          response: 'Test response'
        })

        subscriber.send(:handle_lm_request, event)
      end

      it 'handles prediction events' do
        expect(mock_langfuse).to receive(:span).with(
          hash_including(
            name: "DSPy Prediction",
            input: hash_including(:signature),
            metadata: hash_including(:signature_class)
          )
        ).and_return(mock_span)

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "prediction",
            metadata: hash_including(:signature)
          )
        )

        event = double('Event', payload: {
          signature_class: 'TestSignature',
          status: 'success',
          duration_ms: 200.0,
          input_size: 50
        })

        subscriber.send(:handle_prediction, event)
      end

      it 'handles chain of thought events' do
        expect(mock_langfuse).to receive(:span).with(
          hash_including(
            name: "Chain of Thought",
            input: hash_including(:signature),
            output: hash_including(:reasoning_steps)
          )
        ).and_return(mock_span)

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "chain_of_thought",
            metadata: hash_including(:reasoning_steps)
          )
        )

        event = double('Event', payload: {
          signature_class: 'ReasoningSignature',
          status: 'success',
          duration_ms: 800.0,
          reasoning_steps: 3,
          reasoning_length: 500
        })

        subscriber.send(:handle_chain_of_thought, event)
      end
    end

    describe 'evaluation event handling' do
      it 'handles evaluation start events' do
        expect(mock_langfuse).to receive(:trace).with(
          hash_including(
            name: "DSPy Evaluation",
            metadata: hash_including(:dataset_size)
          )
        ).and_return(mock_trace)

        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "evaluation_started",
            metadata: hash_including(:dataset_size)
          )
        )

        event = double('Event', payload: {
          evaluation_id: 'eval-123',
          dataset_size: 100,
          metric_name: 'accuracy'
        })

        subscriber.send(:handle_evaluation_start, event)
      end

      it 'handles evaluation complete events' do
        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "evaluation_completed",
            metadata: hash_including(:average_score)
          )
        )

        expect(mock_langfuse).to receive(:score).with(
          hash_including(
            name: "evaluation_score",
            value: 0.82
          )
        )

        event = double('Event', payload: {
          evaluation_id: 'eval-123',
          average_score: 0.82,
          scores: [0.8, 0.85, 0.81],
          duration_ms: 3000.0
        })

        subscriber.send(:handle_evaluation_complete, event)
      end
    end

    describe 'context event handling' do
      it 'handles deployment events' do
        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "signature_deployment",
            metadata: hash_including(:signature_name)
          )
        )

        event = double('Event', payload: {
          signature_name: 'TestSignature',
          version: 'v1.0.0',
          performance_score: 0.85
        })

        subscriber.send(:handle_deployment, event)
      end

      it 'handles auto deployment events' do
        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "auto_deployment",
            metadata: hash_including(:signature_name)
          )
        )

        event = double('Event', payload: {
          signature_name: 'TestSignature',
          version: 'v2.0.0'
        })

        subscriber.send(:handle_auto_deployment, event)
      end

      it 'handles automatic rollback events' do
        expect(mock_langfuse).to receive(:event).with(
          hash_including(
            name: "automatic_rollback",
            metadata: hash_including(:performance_drop)
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

    describe 'helper methods' do
      it 'builds usage info from payload' do
        payload = {
          tokens_total: 150,
          tokens_input: 100,
          tokens_output: 50
        }

        usage = subscriber.send(:build_usage_info, payload)
        
        expect(usage).to eq({
          input: 100,
          output: 50,
          total: 150,
          unit: 'TOKENS'
        })
      end

      it 'returns nil when no token information' do
        payload = {}
        usage = subscriber.send(:build_usage_info, payload)
        expect(usage).to be_nil
      end
    end

    describe 'public API' do
      it 'provides access to Langfuse client' do
        expect(subscriber.langfuse_client).to eq(mock_langfuse)
      end

      it 'creates trace manually' do
        expect(mock_langfuse).to receive(:trace).with(
          hash_including(
            name: "Custom Trace",
            metadata: { custom: 'data' }
          )
        ).and_return(mock_trace)

        trace = subscriber.create_trace("Custom Trace", metadata: { custom: 'data' })
        expect(trace).to eq(mock_trace)
      end

      it 'adds score manually' do
        expect(mock_langfuse).to receive(:score).with(
          trace_id: 'trace-123',
          name: 'custom_score',
          value: 0.9,
          comment: 'Custom score'
        )

        subscriber.add_score('trace-123', 'custom_score', 0.9, comment: 'Custom score')
      end

      it 'flushes Langfuse client' do
        expect(mock_langfuse).to receive(:flush)
        subscriber.flush
      end
    end
  end

  context 'when Langfuse is not available' do
    before do
      config.enabled = false
    end

    it 'does not set up Langfuse' do
      expect { subscriber }.not_to raise_error
    end

    it 'handles events gracefully without Langfuse' do
      event = double('Event', payload: { optimization_id: 'test-123' })
      
      expect { subscriber.send(:handle_optimization_start, event) }.not_to raise_error
      expect { subscriber.send(:handle_lm_request, event) }.not_to raise_error
    end

    it 'returns nil for public API methods' do
      expect(subscriber.langfuse_client).to be_nil
      expect(subscriber.create_trace("Test")).to be_nil
      expect { subscriber.add_score('test', 'score', 0.5) }.not_to raise_error
      expect { subscriber.flush }.not_to raise_error
    end
  end

  describe 'event subscription' do
    it 'subscribes to optimization events when enabled' do
      config.enabled = true
      config.trace_optimizations = true
      config.secret_key = 'test_secret'
      
      # Mock Langfuse
      stub_const('Langfuse', double('Langfuse'))
      allow(Langfuse).to receive(:new).and_return(double('Langfuse'))
      
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.start')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.complete')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.trial_start')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.trial_complete')
      expect(DSPy::Instrumentation).to receive(:subscribe).with('dspy.optimization.error')

      # Allow other subscriptions
      allow(DSPy::Instrumentation).to receive(:subscribe)

      DSPy::Subscribers::LangfuseSubscriber.new(config: config)
    end

    it 'does not subscribe when disabled' do
      config.enabled = false
      
      expect(DSPy::Instrumentation).not_to receive(:subscribe)
      
      DSPy::Subscribers::LangfuseSubscriber.new(config: config)
    end
  end
end