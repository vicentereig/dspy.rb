# frozen_string_literal: true

require 'dry-monitor'
require 'dry-configurable'

module DSPy
  # Core instrumentation module using dry-monitor for event emission
  # Provides extension points for logging, Langfuse, New Relic, and custom monitoring
  module Instrumentation
    # Get the current logger subscriber instance (lazy initialization)
    def self.logger_subscriber
      @logger_subscriber ||= begin
        require_relative 'subscribers/logger_subscriber'
        DSPy::Subscribers::LoggerSubscriber.new
      end
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
          status: 'success',
          timestamp: Time.now.iso8601
        )

        self.emit_event(event_name, enhanced_payload)
        result
      rescue => error
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end_cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)

        error_payload = payload.merge(
          duration_ms: ((end_time - start_time) * 1000).round(2),
          cpu_time_ms: ((end_cpu - start_cpu) * 1000).round(2),
          status: 'error',
          error_type: error.class.name,
          error_message: error.message,
          timestamp: Time.now.iso8601
        )

        self.emit_event(event_name, error_payload)
        raise
      end
    end

    # Emit event without timing (for discrete events)
    def self.emit(event_name, payload = {})
      enhanced_payload = payload.merge(
        timestamp: Time.now.iso8601,
        status: payload[:status] || 'success'
      )

      self.emit_event(event_name, enhanced_payload)
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
      # Ensure logger subscriber is initialized
      logger_subscriber
      notifications.instrument(event_name, payload)
    end

    def self.setup_subscribers
      # Lazy initialization - will be created when first accessed
    end
  end
end
