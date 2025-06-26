# frozen_string_literal: true

require 'dry-monitor'
require 'dry-configurable'

module DSPy
  # Core instrumentation module using dry-monitor for event emission
  # Provides extension points for logging, Langfuse, New Relic, and custom monitoring
  module Instrumentation
    extend Dry::Configurable
    extend self

    # Core instrumentation settings
    setting :enabled, default: true
    setting :notifications, default: -> {
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
      end
    }

    # High-precision timing for performance tracking
    def instrument(event_name, payload = {}, &block)
      # If no block is given, return early
      return unless block_given?
      
      # If instrumentation is disabled, just execute the block without timing/events
      unless config.enabled
        return yield
      end

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

        emit_event(event_name, enhanced_payload)
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

        emit_event(event_name, error_payload)
        raise
      end
    end

    # Emit event without timing (for discrete events)
    def emit(event_name, payload = {})
      return unless config.enabled

      enhanced_payload = payload.merge(
        timestamp: Time.now.iso8601,
        status: payload[:status] || 'success'
      )

      emit_event(event_name, enhanced_payload)
    end

    # Register additional events dynamically (useful for testing)
    def self.register_event(event_name)
      notifications = config.notifications.call
      notifications.register_event(event_name)
    end

    # Subscribe to DSPy instrumentation events
    def subscribe(event_pattern = nil, &block)
      return unless config.enabled

      notifications = config.notifications.is_a?(Proc) ? config.notifications.call : config.notifications

      if event_pattern
        notifications.subscribe(event_pattern, &block)
      else
        # Subscribe to all DSPy events
        %w[dspy.lm.request dspy.lm.tokens dspy.lm.response.parsed dspy.predict dspy.predict.validation_error dspy.chain_of_thought dspy.chain_of_thought.reasoning_step dspy.react dspy.react.tool_call dspy.react.iteration_complete dspy.react.max_iterations].each do |event_name|
          notifications.subscribe(event_name, &block)
        end
      end
    end

    private

    def emit_event(event_name, payload)
      return unless config.enabled

      notifications = config.notifications.is_a?(Proc) ? config.notifications.call : config.notifications
      notifications.instrument(event_name, payload)
    end
  end
end
