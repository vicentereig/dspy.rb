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
        
        # Log span start with proper hierarchy
        DSPy.log('span.start', **span_attributes)
        
        # Create OpenTelemetry span if observability is enabled
        otel_span = nil
        if DSPy::Observability.enabled?
          otel_span = DSPy::Observability.start_span(operation, span_attributes)
        end
        
        # Push to stack for child spans
        current[:span_stack].push(span_id)
        
        begin
          result = yield
        ensure
          # Pop from stack
          current[:span_stack].pop
          
          # Log span end with duration
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
          DSPy.log('span.end',
            trace_id: current[:trace_id],
            span_id: span_id,
            duration_ms: duration_ms
          )
          
          # Finish OpenTelemetry span
          DSPy::Observability.finish_span(otel_span) if otel_span
        end
        
        result
      end
      
      def clear!
        Thread.current[:dspy_context] = nil
      end
    end
  end
end