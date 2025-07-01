# frozen_string_literal: true

require 'sorbet-runtime'

begin
  require 'newrelic_rpm'
rescue LoadError
  # New Relic is optional - will be no-op if not available
end

module DSPy
  module Subscribers
    # New Relic subscriber that creates custom metrics and traces for DSPy operations
    # Provides comprehensive monitoring for optimization operations and performance tracking
    class NewrelicSubscriber
      extend T::Sig

      # Configuration for New Relic integration
      class NewrelicConfig
        extend T::Sig

        sig { returns(T::Boolean) }
        attr_accessor :enabled

        sig { returns(String) }
        attr_accessor :app_name

        sig { returns(T::Boolean) }
        attr_accessor :trace_optimization_events

        sig { returns(T::Boolean) }
        attr_accessor :trace_lm_events

        sig { returns(T::Boolean) }
        attr_accessor :record_custom_metrics

        sig { returns(T::Boolean) }
        attr_accessor :record_custom_events

        sig { returns(String) }
        attr_accessor :metric_prefix

        sig { void }
        def initialize
          @enabled = begin
            !!(defined?(NewRelic) && NewRelic::Agent.config[:agent_enabled])
          rescue
            false
          end
          @app_name = begin
            NewRelic::Agent.config[:app_name] || 'DSPy Ruby Application'
          rescue
            'DSPy Ruby Application'
          end
          @trace_optimization_events = true
          @trace_lm_events = true
          @record_custom_metrics = true
          @record_custom_events = true
          @metric_prefix = 'Custom/DSPy'
        end
      end

      sig { returns(NewrelicConfig) }
      attr_reader :config

      sig { params(config: T.nilable(NewrelicConfig)).void }
      def initialize(config: nil)
        @config = config || NewrelicConfig.new
        @optimization_transactions = T.let({}, T::Hash[String, T.untyped])
        
        setup_event_subscriptions if @config.enabled
      end

      private

      sig { void }
      def setup_event_subscriptions
        return unless @config.enabled && defined?(NewRelic)

        # Subscribe to optimization events
        if @config.trace_optimization_events
          setup_optimization_subscriptions
        end

        # Subscribe to LM events
        if @config.trace_lm_events
          setup_lm_subscriptions
        end

        # Subscribe to storage and registry events
        setup_storage_subscriptions
        setup_registry_subscriptions
      end

      sig { void }
      def setup_optimization_subscriptions
        DSPy::Instrumentation.subscribe('dspy.optimization.start') do |event|
          handle_optimization_start(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.complete') do |event|
          handle_optimization_complete(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.trial_start') do |event|
          handle_trial_start(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.trial_complete') do |event|
          handle_trial_complete(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.bootstrap_start') do |event|
          handle_bootstrap_start(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.bootstrap_complete') do |event|
          handle_bootstrap_complete(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.error') do |event|
          handle_optimization_error(event)
        end
      end

      sig { void }
      def setup_lm_subscriptions
        DSPy::Instrumentation.subscribe('dspy.lm.request') do |event|
          handle_lm_request(event)
        end

        DSPy::Instrumentation.subscribe('dspy.predict') do |event|
          handle_prediction(event)
        end

        DSPy::Instrumentation.subscribe('dspy.chain_of_thought') do |event|
          handle_chain_of_thought(event)
        end
      end

      sig { void }
      def setup_storage_subscriptions
        DSPy::Instrumentation.subscribe('dspy.storage.save_complete') do |event|
          handle_storage_operation(event, 'save')
        end

        DSPy::Instrumentation.subscribe('dspy.storage.load_complete') do |event|
          handle_storage_operation(event, 'load')
        end
      end

      sig { void }
      def setup_registry_subscriptions
        DSPy::Instrumentation.subscribe('dspy.registry.register_complete') do |event|
          handle_registry_operation(event, 'register')
        end

        DSPy::Instrumentation.subscribe('dspy.registry.deploy_complete') do |event|
          handle_registry_operation(event, 'deploy')
        end

        DSPy::Instrumentation.subscribe('dspy.registry.rollback_complete') do |event|
          handle_registry_operation(event, 'rollback')
        end

        DSPy::Instrumentation.subscribe('dspy.registry.auto_deployment') do |event|
          handle_auto_deployment(event)
        end

        DSPy::Instrumentation.subscribe('dspy.registry.automatic_rollback') do |event|
          handle_automatic_rollback(event)
        end
      end

      # Optimization event handlers
      sig { params(event: T.untyped).void }
      def handle_optimization_start(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        optimization_id = payload[:optimization_id] || SecureRandom.uuid
        
        # Start custom transaction for optimization
        NewRelic::Agent.start_transaction(
          name: 'DSPy/Optimization',
          category: :task,
          options: {
            custom_params: {
              optimization_id: optimization_id,
              optimizer: payload[:optimizer] || 'unknown',
              trainset_size: payload[:trainset_size],
              valset_size: payload[:valset_size]
            }
          }
        )

        @optimization_transactions[optimization_id] = {
          started_at: Time.now,
          optimizer: payload[:optimizer] || 'unknown'
        }

        # Record custom event
        if @config.record_custom_events
          NewRelic::Agent.record_custom_event('DSPyOptimizationStart', {
            optimization_id: optimization_id,
            optimizer: payload[:optimizer] || 'unknown',
            trainset_size: payload[:trainset_size],
            valset_size: payload[:valset_size],
            timestamp: Time.now.to_f
          })
        end
      end

      sig { params(event: T.untyped).void }
      def handle_optimization_complete(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        optimization_id = payload[:optimization_id]
        transaction_info = @optimization_transactions.delete(optimization_id)
        
        if transaction_info
          # Add custom attributes to the transaction
          NewRelic::Agent.add_custom_attributes({
            'dspy.optimization.status' => 'success',
            'dspy.optimization.duration_ms' => payload[:duration_ms],
            'dspy.optimization.best_score' => payload[:best_score],
            'dspy.optimization.trials_count' => payload[:trials_count],
            'dspy.optimization.optimizer' => transaction_info[:optimizer]
          })

          # Record custom metrics
          if @config.record_custom_metrics
            record_optimization_metrics(payload, transaction_info[:optimizer])
          end

          # Record custom event
          if @config.record_custom_events
            NewRelic::Agent.record_custom_event('DSPyOptimizationComplete', {
              optimization_id: optimization_id,
              optimizer: transaction_info[:optimizer],
              duration_ms: payload[:duration_ms],
              best_score: payload[:best_score],
              trials_count: payload[:trials_count],
              status: 'success',
              timestamp: Time.now.to_f
            })
          end
        end

        # End the transaction
        NewRelic::Agent.end_transaction
      end

      sig { params(event: T.untyped).void }
      def handle_trial_start(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        
        # Create a traced method for this trial
        NewRelic::Agent.record_metric(
          "#{@config.metric_prefix}/Trial/Started",
          1
        ) if @config.record_custom_metrics
      end

      sig { params(event: T.untyped).void }
      def handle_trial_complete(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        status = payload[:status] || 'success'
        
        # Record trial metrics
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Trial/Completed",
            1
          )
          
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Trial/Duration",
            payload[:duration_ms] || 0
          )

          if payload[:score]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Trial/Score",
              payload[:score]
            )
          end

          if status == 'error'
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Trial/Errors",
              1
            )
          end
        end

        # Record custom event
        if @config.record_custom_events
          NewRelic::Agent.record_custom_event('DSPyTrialComplete', {
            optimization_id: payload[:optimization_id],
            trial_number: payload[:trial_number],
            duration_ms: payload[:duration_ms],
            score: payload[:score],
            status: status,
            instruction: payload[:instruction]&.slice(0, 100),
            timestamp: Time.now.to_f
          })
        end
      end

      sig { params(event: T.untyped).void }
      def handle_bootstrap_start(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        
        NewRelic::Agent.record_metric(
          "#{@config.metric_prefix}/Bootstrap/Started",
          1
        ) if @config.record_custom_metrics
      end

      sig { params(event: T.untyped).void }
      def handle_bootstrap_complete(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Bootstrap/Completed",
            1
          )
          
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Bootstrap/Duration",
            payload[:duration_ms] || 0
          )

          if payload[:examples_generated]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Bootstrap/ExamplesGenerated",
              payload[:examples_generated]
            )
          end
        end
      end

      sig { params(event: T.untyped).void }
      def handle_optimization_error(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        optimization_id = payload[:optimization_id]
        transaction_info = @optimization_transactions.delete(optimization_id)
        
        # Record the error
        error_message = payload[:error_message] || 'Unknown optimization error'
        NewRelic::Agent.notice_error(
          StandardError.new(error_message),
          {
            optimization_id: optimization_id,
            optimizer: payload[:optimizer] || 'unknown',
            error_type: payload[:error_type] || 'unknown'
          }
        )

        # Record error metrics
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Optimization/Errors",
            1
          )
        end

        # Record custom event
        if @config.record_custom_events
          NewRelic::Agent.record_custom_event('DSPyOptimizationError', {
            optimization_id: optimization_id,
            optimizer: payload[:optimizer] || 'unknown',
            error_message: error_message,
            error_type: payload[:error_type] || 'unknown',
            timestamp: Time.now.to_f
          })
        end

        # End the transaction with error status
        if transaction_info
          NewRelic::Agent.add_custom_attributes({
            'dspy.optimization.status' => 'error',
            'dspy.optimization.error' => error_message
          })
        end
        
        NewRelic::Agent.end_transaction
      end

      # LM event handlers
      sig { params(event: T.untyped).void }
      def handle_lm_request(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        provider = payload[:provider] || 'unknown'
        model = payload[:gen_ai_request_model] || payload[:model] || 'unknown'
        status = payload[:status] || 'success'
        
        if @config.record_custom_metrics
          # Record LM request metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/LM/Requests",
            1
          )
          
          if payload[:duration_ms]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/LM/Duration",
              payload[:duration_ms]
            )
          end

          if payload[:tokens_total]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/LM/Tokens/Total",
              payload[:tokens_total]
            )
          end

          if payload[:tokens_input]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/LM/Tokens/Input",
              payload[:tokens_input]
            )
          end

          if payload[:tokens_output]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/LM/Tokens/Output",
              payload[:tokens_output]
            )
          end

          if payload[:cost]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/LM/Cost",
              payload[:cost]
            )
          end

          if status == 'error'
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/LM/Errors",
              1
            )
          end
        end

        # Record custom event
        if @config.record_custom_events
          NewRelic::Agent.record_custom_event('DSPyLMRequest', {
            provider: provider,
            model: model,
            status: status,
            duration_ms: payload[:duration_ms],
            tokens_total: payload[:tokens_total],
            tokens_input: payload[:tokens_input],
            tokens_output: payload[:tokens_output],
            cost: payload[:cost],
            error_message: payload[:error_message],
            timestamp: Time.now.to_f
          })
        end
      end

      sig { params(event: T.untyped).void }
      def handle_prediction(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        status = payload[:status] || 'success'
        
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Predict/Requests",
            1
          )
          
          if payload[:duration_ms]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Predict/Duration",
              payload[:duration_ms]
            )
          end

          if status == 'error'
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Predict/Errors",
              1
            )
          end
        end
      end

      sig { params(event: T.untyped).void }
      def handle_chain_of_thought(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        status = payload[:status] || 'success'
        
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/ChainOfThought/Requests",
            1
          )
          
          if payload[:duration_ms]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/ChainOfThought/Duration",
              payload[:duration_ms]
            )
          end

          if payload[:reasoning_steps]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/ChainOfThought/ReasoningSteps",
              payload[:reasoning_steps]
            )
          end

          if status == 'error'
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/ChainOfThought/Errors",
              1
            )
          end
        end
      end

      # Storage event handlers
      sig { params(event: T.untyped, operation: String).void }
      def handle_storage_operation(event, operation)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Storage/#{operation.capitalize}",
            1
          )
          
          if payload[:duration_ms]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Storage/Duration",
              payload[:duration_ms]
            )
          end

          if payload[:size_bytes]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Storage/SizeBytes",
              payload[:size_bytes]
            )
          end
        end
      end

      # Registry event handlers
      sig { params(event: T.untyped, operation: String).void }
      def handle_registry_operation(event, operation)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Registry/#{operation.capitalize}",
            1
          )
          
          if payload[:duration_ms]
            NewRelic::Agent.record_metric(
              "#{@config.metric_prefix}/Registry/Duration",
              payload[:duration_ms]
            )
          end
        end

        # Record custom event
        if @config.record_custom_events
          NewRelic::Agent.record_custom_event("DSPyRegistry#{operation.capitalize}", {
            signature_name: payload[:signature_name],
            version: payload[:version],
            performance_score: payload[:performance_score],
            timestamp: Time.now.to_f
          })
        end
      end

      sig { params(event: T.untyped).void }
      def handle_auto_deployment(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Registry/AutoDeployments",
            1
          )
        end

        if @config.record_custom_events
          NewRelic::Agent.record_custom_event('DSPyAutoDeployment', {
            signature_name: payload[:signature_name],
            version: payload[:version],
            timestamp: Time.now.to_f
          })
        end
      end

      sig { params(event: T.untyped).void }
      def handle_automatic_rollback(event)
        return unless @config.enabled && defined?(NewRelic)

        payload = event.payload
        
        if @config.record_custom_metrics
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Registry/AutoRollbacks",
            1
          )
        end

        if @config.record_custom_events
          NewRelic::Agent.record_custom_event('DSPyAutoRollback', {
            signature_name: payload[:signature_name],
            current_score: payload[:current_score],
            previous_score: payload[:previous_score],
            performance_drop: payload[:performance_drop],
            timestamp: Time.now.to_f
          })
        end
      end

      # Helper methods
      sig { params(payload: T.untyped, optimizer: String).void }
      def record_optimization_metrics(payload, optimizer)
        return unless @config.record_custom_metrics

        if payload[:duration_ms]
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Optimization/Duration",
            payload[:duration_ms]
          )
        end

        if payload[:best_score]
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Optimization/BestScore",
            payload[:best_score]
          )
        end

        if payload[:trials_count]
          NewRelic::Agent.record_metric(
            "#{@config.metric_prefix}/Optimization/TrialsCount",
            payload[:trials_count]
          )
        end

        # Record optimizer-specific metrics
        NewRelic::Agent.record_metric(
          "#{@config.metric_prefix}/Optimization/Completed/#{optimizer}",
          1
        )
      end
    end
  end
end