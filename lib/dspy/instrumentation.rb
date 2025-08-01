# frozen_string_literal: true

require 'dry-monitor'
require 'dry-configurable'
require 'time'
require_relative 'instrumentation/event_payload_factory'

module DSPy
  # Core instrumentation module using dry-monitor for event emission
  # Provides extension points for logging, OpenTelemetry, New Relic, Langfuse, and custom monitoring
  module Instrumentation
    # Get a logger subscriber instance (creates new instance each time)
    def self.logger_subscriber(**options)
      require_relative 'subscribers/logger_subscriber'
      DSPy::Subscribers::LoggerSubscriber.new(**options)
    end

    # Get an OpenTelemetry subscriber instance (creates new instance each time)
    def self.otel_subscriber(**options)
      require_relative 'subscribers/otel_subscriber'
      DSPy::Subscribers::OtelSubscriber.new(**options)
    end

    # Get a New Relic subscriber instance (creates new instance each time)
    def self.newrelic_subscriber(**options)
      require_relative 'subscribers/newrelic_subscriber'
      DSPy::Subscribers::NewrelicSubscriber.new(**options)
    end

    # Get a Langfuse subscriber instance (creates new instance each time)
    def self.langfuse_subscriber(**options)
      require_relative 'subscribers/langfuse_subscriber'
      DSPy::Subscribers::LangfuseSubscriber.new(**options)
    end

    def self.notifications
      @notifications ||= Dry::Monitor::Notifications.new(:dspy).tap do |n|
        # Register all DSPy events
        n.register_event('dspy.lm.request')
        n.register_event('dspy.lm.tokens')
        n.register_event('dspy.lm.response.parsed')
        n.register_event('dspy.predict')
        n.register_event('dspy.predict.validation_error')
        n.register_event('dspy.chain_of_thought')
        n.register_event('dspy.chain_of_thought.reasoning_step')
        n.register_event('dspy.react')
        n.register_event('dspy.react.tool_call')
        n.register_event('dspy.react.iteration_complete')
        n.register_event('dspy.react.max_iterations')
        
        # CodeAct events
        n.register_event('dspy.codeact')
        n.register_event('dspy.codeact.iteration')
        n.register_event('dspy.codeact.code_execution')
        n.register_event('dspy.codeact.iteration_complete')
        n.register_event('dspy.codeact.max_iterations')
        
        # Evaluation events
        n.register_event('dspy.evaluation.start')
        n.register_event('dspy.evaluation.example')
        n.register_event('dspy.evaluation.batch')
        n.register_event('dspy.evaluation.batch_complete')
        
        # Optimization events
        n.register_event('dspy.optimization.start')
        n.register_event('dspy.optimization.complete')
        n.register_event('dspy.optimization.trial_start')
        n.register_event('dspy.optimization.trial_complete')
        n.register_event('dspy.optimization.bootstrap_start')
        n.register_event('dspy.optimization.bootstrap_complete')
        n.register_event('dspy.optimization.bootstrap_example')
        n.register_event('dspy.optimization.minibatch_evaluation')
        n.register_event('dspy.optimization.instruction_proposal_start')
        n.register_event('dspy.optimization.instruction_proposal_complete')
        n.register_event('dspy.optimization.error')
        n.register_event('dspy.optimization.save')
        n.register_event('dspy.optimization.load')
        
        # Storage events
        n.register_event('dspy.storage.save_start')
        n.register_event('dspy.storage.save_complete')
        n.register_event('dspy.storage.save_error')
        n.register_event('dspy.storage.load_start')
        n.register_event('dspy.storage.load_complete')
        n.register_event('dspy.storage.load_error')
        n.register_event('dspy.storage.delete')
        n.register_event('dspy.storage.export')
        n.register_event('dspy.storage.import')
        n.register_event('dspy.storage.cleanup')
        
        # Memory compaction events
        n.register_event('dspy.memory.compaction_check')
        n.register_event('dspy.memory.size_compaction')
        n.register_event('dspy.memory.age_compaction')
        n.register_event('dspy.memory.deduplication')
        n.register_event('dspy.memory.relevance_pruning')
        n.register_event('dspy.memory.compaction_complete')
        
        # Registry events
        n.register_event('dspy.registry.register_start')
        n.register_event('dspy.registry.register_complete')
        n.register_event('dspy.registry.register_error')
        n.register_event('dspy.registry.deploy_start')
        n.register_event('dspy.registry.deploy_complete')
        n.register_event('dspy.registry.deploy_error')
        n.register_event('dspy.registry.rollback_start')
        n.register_event('dspy.registry.rollback_complete')
        n.register_event('dspy.registry.rollback_error')
        n.register_event('dspy.registry.performance_update')
        n.register_event('dspy.registry.export')
        n.register_event('dspy.registry.import')
        n.register_event('dspy.registry.auto_deployment')
        n.register_event('dspy.registry.automatic_rollback')
      end
    end

    # High-precision timing for performance tracking
    def self.instrument(event_name, payload = {}, &block)
      # If no block is given, return early
      return unless block_given?

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      start_cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)

      begin
        result = yield

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end_cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)

        enhanced_payload = payload.merge(
          duration_ms: ((end_time - start_time) * 1000).round(2),
          cpu_time_ms: ((end_cpu - start_cpu) * 1000).round(2),
          status: 'success'
        ).merge(generate_timestamp)

        # Create typed event struct
        event_struct = EventPayloadFactory.create_event(event_name, enhanced_payload)
        self.emit_event(event_name, event_struct)
        result
      rescue => error
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end_cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)

        error_payload = payload.merge(
          duration_ms: ((end_time - start_time) * 1000).round(2),
          cpu_time_ms: ((end_cpu - start_cpu) * 1000).round(2),
          status: 'error',
          error_type: error.class.name,
          error_message: error.message
        ).merge(generate_timestamp)

        # Create typed event struct
        event_struct = EventPayloadFactory.create_event(event_name, error_payload)
        self.emit_event(event_name, event_struct)
        raise
      end
    end

    # Emit event without timing (for discrete events)
    def self.emit(event_name, payload = {})
      # Handle nil payload
      payload ||= {}
      
      enhanced_payload = payload.merge(
        status: payload[:status] || 'success'
      ).merge(generate_timestamp)

      # Create typed event struct
      event_struct = EventPayloadFactory.create_event(event_name, enhanced_payload)
      self.emit_event(event_name, event_struct)
    end

    # Register additional events dynamically (useful for testing)
    def self.register_event(event_name)
      notifications.register_event(event_name)
    end

    # Subscribe to DSPy instrumentation events
    def self.subscribe(event_pattern = nil, &block)
      if event_pattern
        notifications.subscribe(event_pattern, &block)
      else
        # Subscribe to all DSPy events
        %w[dspy.lm.request dspy.lm.tokens dspy.lm.response.parsed dspy.predict dspy.predict.validation_error dspy.chain_of_thought dspy.chain_of_thought.reasoning_step dspy.react dspy.react.tool_call dspy.react.iteration_complete dspy.react.max_iterations].each do |event_name|
          notifications.subscribe(event_name, &block)
        end
      end
    end

    def self.emit_event(event_name, payload)
      # Only emit events - subscribers self-register when explicitly created
      # Convert struct to hash if needed (dry-monitor expects hash)
      if payload.respond_to?(:to_h)
        payload_hash = payload.to_h
        # Restore original timestamp format if needed
        restore_timestamp_format(payload_hash)
      else
        payload_hash = payload
      end
      notifications.instrument(event_name, payload_hash)
    end
    
    # Restore timestamp to original format based on configuration
    def self.restore_timestamp_format(payload_hash)
      return unless payload_hash[:timestamp]
      
      case DSPy.config.instrumentation.timestamp_format
      when DSPy::TimestampFormat::UNIX_NANO
        # Convert ISO8601 back to nanoseconds
        timestamp = Time.parse(payload_hash[:timestamp])
        payload_hash.delete(:timestamp)
        payload_hash[:timestamp_ns] = (timestamp.to_f * 1_000_000_000).to_i
      when DSPy::TimestampFormat::RFC3339_NANO
        # Convert to RFC3339 with nanoseconds
        timestamp = Time.parse(payload_hash[:timestamp])
        payload_hash[:timestamp] = timestamp.strftime('%Y-%m-%dT%H:%M:%S.%9N%z')
      end
    end

    def self.setup_subscribers
      config = DSPy.config.instrumentation
      
      # Return early if instrumentation is disabled
      return unless config.enabled
      
      # Validate configuration first
      DSPy.validate_instrumentation!
      
      # Setup each configured subscriber
      config.subscribers.each do |subscriber_type|
        setup_subscriber(subscriber_type)
      end
    end

    def self.setup_subscriber(subscriber_type)
      case subscriber_type
      when :logger
        setup_logger_subscriber
      when :otel
        setup_otel_subscriber if otel_available?
      when :newrelic
        setup_newrelic_subscriber if newrelic_available?
      when :langfuse
        setup_langfuse_subscriber if langfuse_available?
      else
        raise ArgumentError, "Unknown subscriber type: #{subscriber_type}"
      end
    rescue LoadError => e
      DSPy.logger.warn "Failed to setup #{subscriber_type} subscriber: #{e.message}"
    end

    def self.setup_logger_subscriber
      # Create subscriber - it will read configuration when handling events
      logger_subscriber
    end

    def self.setup_otel_subscriber
      # Create subscriber - it will read configuration when handling events
      otel_subscriber
    end

    def self.setup_newrelic_subscriber
      # Create subscriber - it will read configuration when handling events
      newrelic_subscriber
    end

    def self.setup_langfuse_subscriber
      # Create subscriber - it will read configuration when handling events
      langfuse_subscriber
    end

    # Dependency checking methods
    def self.otel_available?
      begin
        require 'opentelemetry/sdk'
        true
      rescue LoadError
        false
      end
    end

    def self.newrelic_available?
      begin
        require 'newrelic_rpm'
        true
      rescue LoadError
        false
      end
    end

    def self.langfuse_available?
      begin
        require 'langfuse'
        true
      rescue LoadError
        false
      end
    end

    # Generate timestamp in the configured format
    def self.generate_timestamp
      case DSPy.config.instrumentation.timestamp_format
      when DSPy::TimestampFormat::ISO8601
        { timestamp: Time.now.iso8601 }
      when DSPy::TimestampFormat::RFC3339_NANO
        { timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%9N%z') }
      when DSPy::TimestampFormat::UNIX_NANO
        { timestamp_ns: (Time.now.to_f * 1_000_000_000).to_i }
      else
        { timestamp: Time.now.iso8601 }  # Fallback to iso8601
      end
    end

    # Legacy setup method for backward compatibility
    def self.setup_subscribers_legacy
      # Legacy initialization - will be created when first accessed
      # Force initialization of enabled subscribers
      logger_subscriber
      
      # Only initialize if dependencies are available
      begin
        otel_subscriber if ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] || defined?(OpenTelemetry)
      rescue LoadError
        # OpenTelemetry not available, skip
      end

      begin
        newrelic_subscriber if defined?(NewRelic)
      rescue LoadError
        # New Relic not available, skip
      end

      begin
        langfuse_subscriber if ENV['LANGFUSE_SECRET_KEY'] || defined?(Langfuse)
      rescue LoadError
        # Langfuse not available, skip
      end
    end
  end
end
