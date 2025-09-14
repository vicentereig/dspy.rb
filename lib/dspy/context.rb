# frozen_string_literal: true

require 'securerandom'

module DSPy
  class Context
    class << self
      def current
        # Use Thread storage as primary source to ensure thread isolation
        # Fiber storage is used for OpenTelemetry context propagation within the same thread
        
        # Create a unique key for this thread to ensure isolation
        thread_key = :"dspy_context_#{Thread.current.object_id}"
        
        # Always check thread-local storage first for proper isolation
        if Thread.current[thread_key]
          # Thread has context, ensure fiber inherits it for OpenTelemetry propagation
          Fiber[:dspy_context] = Thread.current[thread_key]
          Thread.current[:dspy_context] = Thread.current[thread_key]  # Keep for backward compatibility
          return Thread.current[thread_key]
        end
        
        # Check if current fiber has context that was set by this same thread
        # This handles cases where context was set via OpenTelemetry propagation within the thread
        if Fiber[:dspy_context] && Thread.current[:dspy_context] == Fiber[:dspy_context]
          # This fiber context was set by this thread, safe to use
          Thread.current[thread_key] = Fiber[:dspy_context]
          return Fiber[:dspy_context]
        end
        
        # No existing context or context belongs to different thread - create new one
        context = {
          trace_id: SecureRandom.uuid,
          span_stack: []
        }
        
        # Set in both Thread and Fiber storage
        Thread.current[thread_key] = context
        Thread.current[:dspy_context] = context  # Keep for backward compatibility
        Fiber[:dspy_context] = context
        
        context
      end
      
      def with_span(operation:, **attributes)
        span_id = SecureRandom.uuid
        parent_span_id = current[:span_stack].last
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        # Prepare attributes with context information
        span_attributes = {
          trace_id: current[:trace_id],
          span_id: span_id,
          parent_span_id: parent_span_id,
          operation: operation,
          **attributes
        }
        
        # Log span start with proper hierarchy (internal logging only)
        DSPy.log('span.start', **span_attributes) if DSPy::Observability.enabled?
        
        # Push to stack for child spans tracking
        current[:span_stack].push(span_id)
        
        begin
          # Use OpenTelemetry's proper context management for nesting
          if DSPy::Observability.enabled? && DSPy::Observability.tracer
            # Prepare attributes and add trace name for root spans
            span_attributes = attributes.transform_keys(&:to_s).reject { |k, v| v.nil? }
            
            # Set trace name if this is likely a root span (no parent in our stack)
            if current[:span_stack].length == 1  # This will be the first span
              span_attributes['langfuse.trace.name'] = operation
            end
            
            # Record start time for explicit duration tracking
            otel_start_time = Time.now
            
            # Always use in_span which properly manages context internally
            DSPy::Observability.tracer.in_span(
              operation,
              attributes: span_attributes,
              kind: :internal
            ) do |span|
              result = yield(span)
              
              # Add explicit timing information to help Langfuse
              if span
                duration_ms = ((Time.now - otel_start_time) * 1000).round(3)
                span.set_attribute('duration.ms', duration_ms)
                span.set_attribute('langfuse.observation.startTime', otel_start_time.iso8601(3))
                span.set_attribute('langfuse.observation.endTime', Time.now.iso8601(3))
              end
              
              result
            end
          else
            yield(nil)
          end
        ensure
          # Pop from stack
          current[:span_stack].pop
          
          # Log span end with duration (internal logging only)
          if DSPy::Observability.enabled?
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
            DSPy.log('span.end',
              trace_id: current[:trace_id],
              span_id: span_id,
              duration_ms: duration_ms
            )
          end
        end
      end
      
      def clear!
        # Clear both the thread-specific key and the legacy key
        thread_key = :"dspy_context_#{Thread.current.object_id}"
        Thread.current[thread_key] = nil
        Thread.current[:dspy_context] = nil
        Fiber[:dspy_context] = nil
      end
      
      private
      
      # Check if we're running in an async context
      def in_async_context?
        defined?(Async::Task) && Async::Task.current?
      rescue
        false
      end
    end
  end
end