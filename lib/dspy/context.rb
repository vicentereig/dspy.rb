# frozen_string_literal: true

require 'securerandom'

module DSPy
  class Context
    class << self
      def current
        Thread.current[:dspy_context] ||= {
          trace_id: SecureRandom.uuid,
          span_stack: []
        }
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
        DSPy.log('span.start', **span_attributes)
        
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
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
          DSPy.log('span.end',
            trace_id: current[:trace_id],
            span_id: span_id,
            duration_ms: duration_ms
          )
        end
      end
      
      def clear!
        Thread.current[:dspy_context] = nil
      end
    end
  end
end