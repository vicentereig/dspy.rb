# frozen_string_literal: true

require 'sorbet-runtime'

begin
  require 'langfuse'
rescue LoadError
  # Langfuse is optional - will be no-op if not available
end

module DSPy
  module Subscribers
    # Langfuse subscriber that provides comprehensive LLM observability for DSPy operations
    # Tracks prompts, completions, optimization traces, and performance metrics
    class LangfuseSubscriber
      extend T::Sig

      # Configuration for Langfuse integration
      class LangfuseConfig
        extend T::Sig

        sig { returns(T::Boolean) }
        attr_accessor :enabled

        sig { returns(T.nilable(String)) }
        attr_accessor :public_key

        sig { returns(T.nilable(String)) }
        attr_accessor :secret_key

        sig { returns(T.nilable(String)) }
        attr_accessor :host

        sig { returns(T::Boolean) }
        attr_accessor :trace_optimizations

        sig { returns(T::Boolean) }
        attr_accessor :trace_lm_calls

        sig { returns(T::Boolean) }
        attr_accessor :trace_evaluations

        sig { returns(T::Boolean) }
        attr_accessor :log_prompts

        sig { returns(T::Boolean) }
        attr_accessor :log_completions

        sig { returns(T::Boolean) }
        attr_accessor :calculate_costs

        sig { returns(T::Hash[String, T.untyped]) }
        attr_accessor :default_tags

        sig { void }
        def initialize
          @enabled = !!(defined?(Langfuse) && ENV['LANGFUSE_SECRET_KEY'])
          @public_key = ENV['LANGFUSE_PUBLIC_KEY']
          @secret_key = ENV['LANGFUSE_SECRET_KEY']
          @host = ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
          @trace_optimizations = true
          @trace_lm_calls = true
          @trace_evaluations = true
          @log_prompts = true
          @log_completions = true
          @calculate_costs = true
          @default_tags = { 'framework' => 'dspy-ruby' }
        end
      end

      sig { returns(LangfuseConfig) }
      attr_reader :config

      sig { params(config: T.nilable(LangfuseConfig)).void }
      def initialize(config: nil)
        @config = config || LangfuseConfig.new
        @langfuse = T.let(nil, T.nilable(T.untyped))
        @optimization_traces = T.let({}, T::Hash[String, T.untyped])
        @trial_spans = T.let({}, T::Hash[String, T.untyped])
        @lm_generations = T.let({}, T::Hash[String, T.untyped])
        
        setup_langfuse if @config.enabled
        setup_event_subscriptions
      end

      private

      sig { void }
      def setup_langfuse
        return unless defined?(Langfuse) && @config.secret_key

        @langfuse = Langfuse.new(
          public_key: @config.public_key,
          secret_key: @config.secret_key,
          host: @config.host
        )
      rescue => error
        warn "Failed to setup Langfuse: #{error.message}"
        @config.enabled = false
      end

      sig { void }
      def setup_event_subscriptions
        return unless @config.enabled && @langfuse

        # Subscribe to optimization events
        if @config.trace_optimizations
          setup_optimization_subscriptions
        end

        # Subscribe to LM events
        if @config.trace_lm_calls
          setup_lm_subscriptions
        end

        # Subscribe to evaluation events
        if @config.trace_evaluations
          setup_evaluation_subscriptions
        end

        # Subscribe to storage and registry events for context
        setup_context_subscriptions
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
      def setup_evaluation_subscriptions
        DSPy::Instrumentation.subscribe('dspy.evaluation.start') do |event|
          handle_evaluation_start(event)
        end

        DSPy::Instrumentation.subscribe('dspy.evaluation.batch_complete') do |event|
          handle_evaluation_complete(event)
        end
      end

      sig { void }
      def setup_context_subscriptions
        DSPy::Instrumentation.subscribe('dspy.registry.deploy_complete') do |event|
          handle_deployment(event)
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
        return unless @langfuse

        payload = event.payload
        optimization_id = payload[:optimization_id] || SecureRandom.uuid
        
        trace = @langfuse.trace(
          id: optimization_id,
          name: "DSPy Optimization",
          metadata: {
            optimizer: payload[:optimizer] || 'unknown',
            trainset_size: payload[:trainset_size],
            valset_size: payload[:valset_size],
            config: payload[:config]
          },
          tags: @config.default_tags.merge(
            'operation' => 'optimization',
            'optimizer' => payload[:optimizer] || 'unknown'
          )
        )

        @optimization_traces[optimization_id] = trace

        # Log optimization event
        @langfuse.event(
          trace_id: optimization_id,
          name: "optimization_started",
          metadata: {
            optimizer: payload[:optimizer],
            dataset_sizes: {
              train: payload[:trainset_size],
              validation: payload[:valset_size]
            }
          }
        )
      end

      sig { params(event: T.untyped).void }
      def handle_optimization_complete(event)
        return unless @langfuse

        payload = event.payload
        optimization_id = payload[:optimization_id]
        trace = @optimization_traces.delete(optimization_id)
        
        return unless trace

        # Update trace with final results
        trace.update(
          output: {
            best_score: payload[:best_score],
            trials_count: payload[:trials_count],
            final_instruction: payload[:final_instruction]
          },
          metadata: {
            duration_ms: payload[:duration_ms],
            status: 'success'
          }
        )

        # Log completion event
        @langfuse.event(
          trace_id: optimization_id,
          name: "optimization_completed",
          metadata: {
            best_score: payload[:best_score],
            trials_count: payload[:trials_count],
            duration_ms: payload[:duration_ms]
          }
        )

        # Calculate and log optimization score
        if payload[:best_score]
          @langfuse.score(
            trace_id: optimization_id,
            name: "optimization_performance",
            value: payload[:best_score],
            comment: "Best optimization score achieved"
          )
        end
      end

      sig { params(event: T.untyped).void }
      def handle_trial_start(event)
        return unless @langfuse

        payload = event.payload
        optimization_id = payload[:optimization_id]
        trial_id = "#{optimization_id}_#{payload[:trial_number]}"
        
        span = @langfuse.span(
          trace_id: optimization_id,
          name: "Optimization Trial",
          input: {
            trial_number: payload[:trial_number],
            instruction: payload[:instruction],
            examples_count: payload[:examples_count]
          },
          metadata: {
            trial_number: payload[:trial_number]
          }
        )

        @trial_spans[trial_id] = span

        # Log trial event
        @langfuse.event(
          trace_id: optimization_id,
          name: "trial_started",
          metadata: {
            trial_number: payload[:trial_number],
            instruction_preview: payload[:instruction]&.slice(0, 100)
          }
        )
      end

      sig { params(event: T.untyped).void }
      def handle_trial_complete(event)
        return unless @langfuse

        payload = event.payload
        optimization_id = payload[:optimization_id]
        trial_id = "#{optimization_id}_#{payload[:trial_number]}"
        span = @trial_spans.delete(trial_id)
        
        return unless span

        status = payload[:status] || 'success'
        
        # Update span with results
        span.update(
          output: {
            score: payload[:score],
            status: status
          },
          metadata: {
            duration_ms: payload[:duration_ms],
            error: payload[:error_message]
          },
          level: status == 'error' ? 'ERROR' : 'INFO'
        )

        # Log trial completion
        @langfuse.event(
          trace_id: optimization_id,
          name: "trial_completed",
          metadata: {
            trial_number: payload[:trial_number],
            score: payload[:score],
            status: status,
            duration_ms: payload[:duration_ms]
          }
        )

        # Add score if available
        if payload[:score]
          @langfuse.score(
            trace_id: optimization_id,
            name: "trial_score",
            value: payload[:score],
            comment: "Trial #{payload[:trial_number]} score"
          )
        end
      end

      sig { params(event: T.untyped).void }
      def handle_optimization_error(event)
        return unless @langfuse

        payload = event.payload
        optimization_id = payload[:optimization_id]
        trace = @optimization_traces.delete(optimization_id)
        
        if trace
          trace.update(
            output: {
              error: payload[:error_message],
              error_type: payload[:error_type]
            },
            metadata: {
              status: 'error'
            },
            level: 'ERROR'
          )
        end

        # Log error event
        @langfuse.event(
          trace_id: optimization_id,
          name: "optimization_error",
          metadata: {
            error_message: payload[:error_message],
            error_type: payload[:error_type],
            optimizer: payload[:optimizer]
          }
        )
      end

      # LM event handlers
      sig { params(event: T.untyped).void }
      def handle_lm_request(event)
        return unless @langfuse

        payload = event.payload
        request_id = payload[:request_id] || SecureRandom.uuid
        
        # Create generation for LM request
        generation = @langfuse.generation(
          name: "LM Request",
          model: payload[:gen_ai_request_model] || payload[:model] || 'unknown',
          input: @config.log_prompts ? payload[:prompt] : nil,
          output: @config.log_completions ? payload[:response] : nil,
          metadata: {
            provider: payload[:provider],
            status: payload[:status],
            duration_ms: payload[:duration_ms]
          },
          usage: build_usage_info(payload),
          level: payload[:status] == 'error' ? 'ERROR' : 'INFO'
        )

        @lm_generations[request_id] = generation

        # Log LM request event
        @langfuse.event(
          name: "lm_request",
          metadata: {
            provider: payload[:provider],
            model: payload[:gen_ai_request_model] || payload[:model],
            status: payload[:status],
            duration_ms: payload[:duration_ms],
            tokens_total: payload[:tokens_total],
            cost: payload[:cost]
          }
        )

        # Add cost information if available
        if payload[:cost] && @config.calculate_costs
          @langfuse.score(
            name: "request_cost",
            value: payload[:cost],
            comment: "Cost of LM request"
          )
        end
      end

      sig { params(event: T.untyped).void }
      def handle_prediction(event)
        return unless @langfuse

        payload = event.payload
        
        # Create span for prediction
        span = @langfuse.span(
          name: "DSPy Prediction",
          input: {
            signature: payload[:signature_class],
            input_size: payload[:input_size]
          },
          metadata: {
            signature_class: payload[:signature_class],
            status: payload[:status],
            duration_ms: payload[:duration_ms]
          },
          level: payload[:status] == 'error' ? 'ERROR' : 'INFO'
        )

        # Log prediction event
        @langfuse.event(
          name: "prediction",
          metadata: {
            signature: payload[:signature_class],
            status: payload[:status],
            duration_ms: payload[:duration_ms]
          }
        )
      end

      sig { params(event: T.untyped).void }
      def handle_chain_of_thought(event)
        return unless @langfuse

        payload = event.payload
        
        # Create span for chain of thought
        span = @langfuse.span(
          name: "Chain of Thought",
          input: {
            signature: payload[:signature_class]
          },
          output: {
            reasoning_steps: payload[:reasoning_steps],
            reasoning_length: payload[:reasoning_length]
          },
          metadata: {
            signature_class: payload[:signature_class],
            status: payload[:status],
            duration_ms: payload[:duration_ms]
          },
          level: payload[:status] == 'error' ? 'ERROR' : 'INFO'
        )

        # Log chain of thought event
        @langfuse.event(
          name: "chain_of_thought",
          metadata: {
            signature: payload[:signature_class],
            reasoning_steps: payload[:reasoning_steps],
            status: payload[:status],
            duration_ms: payload[:duration_ms]
          }
        )
      end

      # Evaluation event handlers
      sig { params(event: T.untyped).void }
      def handle_evaluation_start(event)
        return unless @langfuse

        payload = event.payload
        evaluation_id = payload[:evaluation_id] || SecureRandom.uuid
        
        # Create trace for evaluation
        trace = @langfuse.trace(
          id: evaluation_id,
          name: "DSPy Evaluation",
          metadata: {
            dataset_size: payload[:dataset_size],
            metric_name: payload[:metric_name]
          },
          tags: @config.default_tags.merge(
            'operation' => 'evaluation'
          )
        )

        # Log evaluation start
        @langfuse.event(
          trace_id: evaluation_id,
          name: "evaluation_started",
          metadata: {
            dataset_size: payload[:dataset_size],
            metric_name: payload[:metric_name]
          }
        )
      end

      sig { params(event: T.untyped).void }
      def handle_evaluation_complete(event)
        return unless @langfuse

        payload = event.payload
        evaluation_id = payload[:evaluation_id]
        
        # Log evaluation completion
        @langfuse.event(
          trace_id: evaluation_id,
          name: "evaluation_completed",
          metadata: {
            average_score: payload[:average_score],
            scores: payload[:scores],
            duration_ms: payload[:duration_ms]
          }
        )

        # Add evaluation score
        if payload[:average_score]
          @langfuse.score(
            trace_id: evaluation_id,
            name: "evaluation_score",
            value: payload[:average_score],
            comment: "Average evaluation score"
          )
        end
      end

      # Context event handlers
      sig { params(event: T.untyped).void }
      def handle_deployment(event)
        return unless @langfuse

        payload = event.payload
        
        @langfuse.event(
          name: "signature_deployment",
          metadata: {
            signature_name: payload[:signature_name],
            version: payload[:version],
            performance_score: payload[:performance_score]
          }
        )
      end

      sig { params(event: T.untyped).void }
      def handle_auto_deployment(event)
        return unless @langfuse

        payload = event.payload
        
        @langfuse.event(
          name: "auto_deployment",
          metadata: {
            signature_name: payload[:signature_name],
            version: payload[:version],
            trigger: 'automatic'
          }
        )
      end

      sig { params(event: T.untyped).void }
      def handle_automatic_rollback(event)
        return unless @langfuse

        payload = event.payload
        
        @langfuse.event(
          name: "automatic_rollback",
          metadata: {
            signature_name: payload[:signature_name],
            current_score: payload[:current_score],
            previous_score: payload[:previous_score],
            performance_drop: payload[:performance_drop]
          }
        )
      end

      # Helper methods
      sig { params(payload: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_usage_info(payload)
        return nil unless payload[:tokens_total] || payload[:tokens_input] || payload[:tokens_output]

        usage = {}
        usage[:input] = payload[:tokens_input] if payload[:tokens_input]
        usage[:output] = payload[:tokens_output] if payload[:tokens_output]
        usage[:total] = payload[:tokens_total] if payload[:tokens_total]
        usage[:unit] = 'TOKENS'
        
        usage
      end

      public

      # Public API for manual tracing
      sig { returns(T.nilable(T.untyped)) }
      def langfuse_client
        @langfuse
      end

      sig { params(name: String, metadata: T::Hash[Symbol, T.untyped]).returns(T.nilable(T.untyped)) }
      def create_trace(name, metadata: {})
        return nil unless @langfuse
        
        @langfuse.trace(
          name: name,
          metadata: metadata,
          tags: @config.default_tags
        )
      end

      sig { params(trace_id: String, name: String, value: Float, comment: T.nilable(String)).void }
      def add_score(trace_id, name, value, comment: nil)
        return unless @langfuse
        
        @langfuse.score(
          trace_id: trace_id,
          name: name,
          value: value,
          comment: comment
        )
      end

      sig { void }
      def flush
        return unless @langfuse
        
        @langfuse.flush
      end
    end
  end
end