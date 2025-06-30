# frozen_string_literal: true

require 'sorbet-runtime'

begin
  require 'opentelemetry/api'
  require 'opentelemetry/sdk'
  require 'opentelemetry/exporter/otlp'
rescue LoadError
  # OpenTelemetry is optional - will be no-op if not available
end

module DSPy
  module Subscribers
    # OpenTelemetry subscriber that creates spans and metrics for DSPy operations
    # Provides comprehensive tracing for optimization operations and LM calls
    class OtelSubscriber
      extend T::Sig

      # Configuration for OpenTelemetry integration
      class OtelConfig
        extend T::Sig

        sig { returns(T::Boolean) }
        attr_accessor :enabled

        sig { returns(String) }
        attr_accessor :service_name

        sig { returns(String) }
        attr_accessor :service_version

        sig { returns(T.nilable(String)) }
        attr_accessor :endpoint

        sig { returns(T::Hash[String, String]) }
        attr_accessor :headers

        sig { returns(T::Boolean) }
        attr_accessor :trace_optimization_events

        sig { returns(T::Boolean) }
        attr_accessor :trace_lm_events

        sig { returns(T::Boolean) }
        attr_accessor :export_metrics

        sig { returns(Float) }
        attr_accessor :sample_rate

        sig { void }
        def initialize
          @enabled = !!(defined?(OpenTelemetry) && ENV['OTEL_EXPORTER_OTLP_ENDPOINT'])
          @service_name = ENV.fetch('OTEL_SERVICE_NAME', 'dspy-ruby')
          @service_version = begin
            ENV.fetch('OTEL_SERVICE_VERSION', DSPy::VERSION)
          rescue
            '1.0.0'
          end
          @endpoint = ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
          @headers = parse_headers(ENV['OTEL_EXPORTER_OTLP_HEADERS'])
          @trace_optimization_events = true
          @trace_lm_events = true
          @export_metrics = true
          @sample_rate = ENV.fetch('OTEL_TRACE_SAMPLE_RATE', '1.0').to_f
        end

        private

        sig { params(headers_str: T.nilable(String)).returns(T::Hash[String, String]) }
        def parse_headers(headers_str)
          return {} unless headers_str

          headers_str.split(',').each_with_object({}) do |header, hash|
            key, value = header.split('=', 2)
            hash[key.strip] = value&.strip || ''
          end
        end
      end

      sig { returns(OtelConfig) }
      attr_reader :config

      sig { params(config: T.nilable(OtelConfig)).void }
      def initialize(config: nil)
        @config = config || OtelConfig.new
        @tracer = T.let(nil, T.nilable(T.untyped))
        @meter = T.let(nil, T.nilable(T.untyped))
        @optimization_spans = T.let({}, T::Hash[String, T.untyped])
        @trial_spans = T.let({}, T::Hash[String, T.untyped])
        
        setup_opentelemetry if @config.enabled
        setup_event_subscriptions
      end

      private

      sig { void }
      def setup_opentelemetry
        return unless defined?(OpenTelemetry)

        # Configure OpenTelemetry
        OpenTelemetry::SDK.configure do |c|
          c.service_name = @config.service_name
          c.service_version = @config.service_version
          
          if @config.endpoint
            c.add_span_processor(
              OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
                OpenTelemetry::Exporter::OTLP::Exporter.new(
                  endpoint: @config.endpoint,
                  headers: @config.headers
                )
              )
            )
          end
        end

        version = begin
          DSPy::VERSION
        rescue
          '1.0.0'
        end
        
        @tracer = OpenTelemetry.tracer_provider.tracer('dspy-ruby', version)
        @meter = OpenTelemetry.meter_provider.meter('dspy-ruby', version) if @config.export_metrics
      rescue => error
        warn "Failed to setup OpenTelemetry: #{error.message}"
        @config.enabled = false
      end

      sig { void }
      def setup_event_subscriptions
        return unless @config.enabled && @tracer

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
        DSPy::Instrumentation.subscribe('dspy.storage.save_start') do |event|
          handle_storage_operation(event, 'save')
        end

        DSPy::Instrumentation.subscribe('dspy.storage.load_start') do |event|
          handle_storage_operation(event, 'load')
        end
      end

      sig { void }
      def setup_registry_subscriptions
        DSPy::Instrumentation.subscribe('dspy.registry.register_start') do |event|
          handle_registry_operation(event, 'register')
        end

        DSPy::Instrumentation.subscribe('dspy.registry.deploy_start') do |event|
          handle_registry_operation(event, 'deploy')
        end

        DSPy::Instrumentation.subscribe('dspy.registry.rollback_start') do |event|
          handle_registry_operation(event, 'rollback')
        end
      end

      # Optimization event handlers
      sig { params(event: T.untyped).void }
      def handle_optimization_start(event)
        return unless @tracer

        payload = event.payload
        optimization_id = payload[:optimization_id] || SecureRandom.uuid
        
        span = @tracer.start_span(
          'dspy.optimization',
          attributes: {
            'dspy.operation' => 'optimization',
            'dspy.optimization.id' => optimization_id,
            'dspy.optimization.optimizer' => payload[:optimizer] || 'unknown',
            'dspy.optimization.trainset_size' => payload[:trainset_size],
            'dspy.optimization.valset_size' => payload[:valset_size],
            'dspy.optimization.config' => payload[:config]&.to_s
          }
        )

        @optimization_spans[optimization_id] = span
        
        # Add metrics
        if @meter
          @meter.create_counter(
            'dspy.optimization.started',
            description: 'Number of optimizations started'
          ).add(1, attributes: {
            'optimizer' => payload[:optimizer] || 'unknown'
          })
        end
      end

      sig { params(event: T.untyped).void }
      def handle_optimization_complete(event)
        return unless @tracer

        payload = event.payload
        optimization_id = payload[:optimization_id]
        span = @optimization_spans.delete(optimization_id)
        
        return unless span

        span.set_attribute('dspy.optimization.status', 'success')
        span.set_attribute('dspy.optimization.duration_ms', payload[:duration_ms])
        span.set_attribute('dspy.optimization.best_score', payload[:best_score])
        span.set_attribute('dspy.optimization.trials_count', payload[:trials_count])
        span.set_attribute('dspy.optimization.final_instruction', payload[:final_instruction]&.truncate(500))

        span.finish

        # Record metrics
        if @meter && payload[:duration_ms]
          @meter.create_histogram(
            'dspy.optimization.duration',
            description: 'Optimization duration in milliseconds'
          ).record(payload[:duration_ms], attributes: {
            'optimizer' => payload[:optimizer] || 'unknown',
            'status' => 'success'
          })

          if payload[:best_score]
            @meter.create_histogram(
              'dspy.optimization.score',
              description: 'Best optimization score achieved'
            ).record(payload[:best_score], attributes: {
              'optimizer' => payload[:optimizer] || 'unknown'
            })
          end
        end
      end

      sig { params(event: T.untyped).void }
      def handle_trial_start(event)
        return unless @tracer

        payload = event.payload
        trial_id = "#{payload[:optimization_id]}_#{payload[:trial_number]}"
        
        span = @tracer.start_span(
          'dspy.optimization.trial',
          attributes: {
            'dspy.operation' => 'optimization_trial',
            'dspy.trial.id' => trial_id,
            'dspy.trial.number' => payload[:trial_number],
            'dspy.trial.instruction' => payload[:instruction]&.truncate(200),
            'dspy.trial.examples_count' => payload[:examples_count]
          }
        )

        @trial_spans[trial_id] = span
      end

      sig { params(event: T.untyped).void }
      def handle_trial_complete(event)
        return unless @tracer

        payload = event.payload
        trial_id = "#{payload[:optimization_id]}_#{payload[:trial_number]}"
        span = @trial_spans.delete(trial_id)
        
        return unless span

        span.set_attribute('dspy.trial.status', payload[:status] || 'success')
        span.set_attribute('dspy.trial.duration_ms', payload[:duration_ms])
        span.set_attribute('dspy.trial.score', payload[:score]) if payload[:score]
        span.set_attribute('dspy.trial.error', payload[:error_message]) if payload[:error_message]

        if payload[:status] == 'error'
          span.record_exception(payload[:error_message] || 'Unknown error')
          span.status = OpenTelemetry::Trace::Status.error('Trial failed')
        end

        span.finish
      end

      sig { params(event: T.untyped).void }
      def handle_bootstrap_start(event)
        return unless @tracer

        payload = event.payload
        
        @tracer.in_span(
          'dspy.optimization.bootstrap',
          attributes: {
            'dspy.operation' => 'bootstrap',
            'dspy.bootstrap.target_count' => payload[:target_count],
            'dspy.bootstrap.trainset_size' => payload[:trainset_size]
          }
        ) do |span|
          # Span will be automatically finished when block exits
        end
      end

      sig { params(event: T.untyped).void }
      def handle_bootstrap_complete(event)
        # Bootstrap complete is handled by the span from bootstrap_start
      end

      sig { params(event: T.untyped).void }
      def handle_optimization_error(event)
        return unless @tracer

        payload = event.payload
        optimization_id = payload[:optimization_id]
        span = @optimization_spans.delete(optimization_id)
        
        if span
          span.set_attribute('dspy.optimization.status', 'error')
          span.set_attribute('dspy.optimization.error', payload[:error_message])
          span.record_exception(payload[:error_message] || 'Unknown optimization error')
          span.status = OpenTelemetry::Trace::Status.error('Optimization failed')
          span.finish
        end

        # Record error metrics
        if @meter
          @meter.create_counter(
            'dspy.optimization.errors',
            description: 'Number of optimization errors'
          ).add(1, attributes: {
            'optimizer' => payload[:optimizer] || 'unknown',
            'error_type' => payload[:error_type] || 'unknown'
          })
        end
      end

      # LM event handlers
      sig { params(event: T.untyped).void }
      def handle_lm_request(event)
        return unless @tracer

        payload = event.payload
        
        @tracer.in_span(
          'dspy.lm.request',
          attributes: {
            'dspy.operation' => 'lm_request',
            'dspy.lm.provider' => payload[:provider],
            'dspy.lm.model' => payload[:gen_ai_request_model] || payload[:model],
            'dspy.lm.status' => payload[:status],
            'dspy.lm.duration_ms' => payload[:duration_ms],
            'dspy.lm.tokens_total' => payload[:tokens_total],
            'dspy.lm.tokens_input' => payload[:tokens_input],
            'dspy.lm.tokens_output' => payload[:tokens_output],
            'dspy.lm.cost' => payload[:cost]
          }
        ) do |span|
          if payload[:status] == 'error'
            span.record_exception(payload[:error_message] || 'LM request failed')
            span.status = OpenTelemetry::Trace::Status.error('LM request failed')
          end

          # Record metrics
          if @meter
            if payload[:duration_ms]
              @meter.create_histogram(
                'dspy.lm.request.duration',
                description: 'LM request duration in milliseconds'
              ).record(payload[:duration_ms], attributes: {
                'provider' => payload[:provider],
                'model' => payload[:gen_ai_request_model] || payload[:model],
                'status' => payload[:status]
              })
            end

            if payload[:tokens_total]
              @meter.create_histogram(
                'dspy.lm.tokens.total',
                description: 'Total tokens used in LM request'
              ).record(payload[:tokens_total], attributes: {
                'provider' => payload[:provider],
                'model' => payload[:gen_ai_request_model] || payload[:model]
              })
            end

            if payload[:cost]
              @meter.create_histogram(
                'dspy.lm.cost',
                description: 'Cost of LM request'
              ).record(payload[:cost], attributes: {
                'provider' => payload[:provider],
                'model' => payload[:gen_ai_request_model] || payload[:model]
              })
            end
          end
        end
      end

      sig { params(event: T.untyped).void }
      def handle_prediction(event)
        return unless @tracer

        payload = event.payload
        
        @tracer.in_span(
          'dspy.predict',
          attributes: {
            'dspy.operation' => 'predict',
            'dspy.signature' => payload[:signature_class],
            'dspy.predict.status' => payload[:status],
            'dspy.predict.duration_ms' => payload[:duration_ms],
            'dspy.predict.input_size' => payload[:input_size]
          }
        ) do |span|
          if payload[:status] == 'error'
            span.record_exception(payload[:error_message] || 'Prediction failed')
            span.status = OpenTelemetry::Trace::Status.error('Prediction failed')
          end
        end
      end

      sig { params(event: T.untyped).void }
      def handle_chain_of_thought(event)
        return unless @tracer

        payload = event.payload
        
        @tracer.in_span(
          'dspy.chain_of_thought',
          attributes: {
            'dspy.operation' => 'chain_of_thought',
            'dspy.signature' => payload[:signature_class],
            'dspy.cot.status' => payload[:status],
            'dspy.cot.duration_ms' => payload[:duration_ms],
            'dspy.cot.reasoning_steps' => payload[:reasoning_steps],
            'dspy.cot.reasoning_length' => payload[:reasoning_length]
          }
        ) do |span|
          if payload[:status] == 'error'
            span.record_exception(payload[:error_message] || 'Chain of thought failed')
            span.status = OpenTelemetry::Trace::Status.error('Chain of thought failed')
          end
        end
      end

      # Storage event handlers
      sig { params(event: T.untyped, operation: String).void }
      def handle_storage_operation(event, operation)
        return unless @tracer

        payload = event.payload
        
        @tracer.in_span(
          "dspy.storage.#{operation}",
          attributes: {
            'dspy.operation' => "storage_#{operation}",
            'dspy.storage.program_id' => payload[:program_id],
            'dspy.storage.size_bytes' => payload[:size_bytes]
          }
        ) do |span|
          # Span will auto-complete
        end
      end

      # Registry event handlers  
      sig { params(event: T.untyped, operation: String).void }
      def handle_registry_operation(event, operation)
        return unless @tracer

        payload = event.payload
        
        @tracer.in_span(
          "dspy.registry.#{operation}",
          attributes: {
            'dspy.operation' => "registry_#{operation}",
            'dspy.registry.signature_name' => payload[:signature_name],
            'dspy.registry.version' => payload[:version]
          }
        ) do |span|
          # Span will auto-complete
        end
      end
    end
  end
end