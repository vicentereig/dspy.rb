# frozen_string_literal: true

require 'securerandom'
require 'json'

module DSPy
  class Context
    class << self
      def current
        # Prefer fiber-local context for async safety; fall back to thread root context.
        fiber_context = Fiber[:dspy_context]
        if fiber_context && fiber_context[:thread_id] == Thread.current.object_id
          return fiber_context if fiber_context[:fiber_id] == Fiber.current.object_id

          Fiber[:dspy_context] = fork_context(fiber_context)
          return Fiber[:dspy_context]
        end

        thread_key = :"dspy_context_#{Thread.current.object_id}"
        thread_context = Thread.current[thread_key]

        if thread_context
          Fiber[:dspy_context] = fork_context(thread_context)
          return Fiber[:dspy_context]
        end

        context = build_context
        Thread.current[thread_key] = context
        Thread.current[:dspy_context] = context  # Backward compatibility (thread root)
        Fiber[:dspy_context] = context
        context
      end

      def with_request(request_id, start_time)
        previous_request_id = current[:request_id]
        previous_start_time = current[:request_start_time]

        current[:request_id] = request_id
        current[:request_start_time] = start_time
        yield
      ensure
        current[:request_id] = previous_request_id
        current[:request_start_time] = previous_start_time
      end

      def fork_context(parent_context)
        clone_context(parent_context)
      end
      
      def with_span(operation:, **attributes)
        span_id = SecureRandom.uuid
        parent_span_id = current[:span_stack].last
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sanitized_attributes = sanitize_span_attributes(attributes)

        # Prepare attributes with context information
        span_attributes = {
          trace_id: current[:trace_id],
          span_id: span_id,
          parent_span_id: parent_span_id,
          operation: operation,
          **sanitized_attributes
        }
        
        # Log span start with proper hierarchy (internal logging only)
        DSPy.log('span.start', **span_attributes) if DSPy::Observability.enabled?
        
        # Push to stack for child spans tracking
        current[:span_stack].push(span_id)
        
        begin
          # Use OpenTelemetry's proper context management for nesting
          if DSPy::Observability.enabled? && DSPy::Observability.tracer
            # Prepare attributes and add trace name for root spans
            span_attributes = sanitized_attributes.transform_keys(&:to_s).reject { |k, v| v.nil? }
            
            # Set trace name if this is likely a root span (no parent in our stack)
            if current[:span_stack].length == 1  # This will be the first span
              span_attributes['langfuse.trace.name'] = operation
            end
            
            # Record start time for explicit duration tracking
            otel_start_time = Time.now
            
            # Get parent OpenTelemetry span for proper context propagation
            parent_otel_span = current[:otel_span_stack].last
            
            # Create span with proper parent context
            if parent_otel_span
              # Use the parent span's context to ensure proper nesting
              OpenTelemetry::Trace.with_span(parent_otel_span) do
                DSPy::Observability.tracer.in_span(
                  operation,
                  attributes: span_attributes,
                  kind: :internal
                ) do |span|
                  # Add to our OpenTelemetry span stack
                  current[:otel_span_stack].push(span)
                  
                  begin
                    result = yield(span)
                    
                    # Add explicit timing information to help Langfuse
                    if span
                      duration_ms = ((Time.now - otel_start_time) * 1000).round(3)
                      span.set_attribute('duration.ms', duration_ms)
                      span.set_attribute('langfuse.observation.startTime', otel_start_time.iso8601(3))
                      span.set_attribute('langfuse.observation.endTime', Time.now.iso8601(3))
                    end
                    
                    result
                  ensure
                    # Remove from our OpenTelemetry span stack
                    current[:otel_span_stack].pop
                  end
                end
              end
            else
              # Root span - no parent context needed
              DSPy::Observability.tracer.in_span(
                operation,
                attributes: span_attributes,
                kind: :internal
              ) do |span|
                # Add to our OpenTelemetry span stack
                current[:otel_span_stack].push(span)
                
                begin
                  result = yield(span)
                  
                  # Add explicit timing information to help Langfuse
                  if span
                    duration_ms = ((Time.now - otel_start_time) * 1000).round(3)
                    span.set_attribute('duration.ms', duration_ms)
                    span.set_attribute('langfuse.observation.startTime', otel_start_time.iso8601(3))
                    span.set_attribute('langfuse.observation.endTime', Time.now.iso8601(3))
                  end
                  
                  result
                ensure
                  # Remove from our OpenTelemetry span stack
                  current[:otel_span_stack].pop
                end
              end
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

      def with_module(module_instance, label: nil)
        stack = module_stack
        entry = build_module_entry(module_instance, label)
        stack.push(entry)
        yield
      ensure
        if stack.last.equal?(entry)
          stack.pop
        else
          stack.delete(entry)
        end
      end

      def module_stack
        current[:module_stack] ||= []
      end

      def module_context_attributes
        stack = module_stack
        return {} if stack.empty?

        path = stack.map do |entry|
          {
            id: entry[:id],
            class: entry[:class],
            label: entry[:label]
          }
        end

        ancestry_token = path.map { |node| node[:id] }.join('>')

        {
          module_path: path,
          module_root: path.first,
          module_leaf: path.last,
          module_scope: {
            ancestry_token: ancestry_token,
            depth: path.length
          }
        }
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

      def build_context
        {
          trace_id: SecureRandom.uuid,
          thread_id: Thread.current.object_id,
          fiber_id: Fiber.current.object_id,
          span_stack: [],
          otel_span_stack: [],
          module_stack: [],
          request_id: nil,
          request_start_time: nil
        }
      end

      def clone_context(context)
        cloned = context.dup
        cloned[:span_stack] = Array(context[:span_stack]).dup
        cloned[:otel_span_stack] = Array(context[:otel_span_stack]).dup
        cloned[:module_stack] = Array(context[:module_stack]).map { |entry| entry.dup }
        cloned[:thread_id] = Thread.current.object_id
        cloned[:fiber_id] = Fiber.current.object_id
        cloned[:request_id] = context[:request_id]
        cloned[:request_start_time] = context[:request_start_time]
        cloned
      end

      def sanitize_span_attributes(attributes)
        attributes.each_with_object({}) do |(key, value), acc|
          sanitized_value = sanitize_attribute_value(value)
          acc[key] = sanitized_value
        end
      end

      def sanitize_attribute_value(value)
        case value
        when nil, String, Integer, Float, TrueClass, FalseClass
          value
        when Time
          value.iso8601(3)
        when Array
          begin
            JSON.generate(value.map { |item| sanitize_attribute_value(item) })
          rescue StandardError
            value.map(&:to_s).to_s
          end
        when Hash
          begin
            sanitized_hash = value.each_with_object({}) do |(k, v), hash|
              sanitized = sanitize_attribute_value(v)
              hash[k.to_s] = sanitized unless sanitized.nil?
            end
            JSON.generate(sanitized_hash)
          rescue StandardError
            value.to_s
          end
        else
          if defined?(T::Struct) && value.is_a?(T::Struct)
            begin
              struct_hash = value.to_h.transform_keys(&:to_s).transform_values { |v| sanitize_attribute_value(v) }
              JSON.generate(struct_hash)
            rescue StandardError
              value.to_s
            end
          else
            value.respond_to?(:to_json) ? value.to_json : value.to_s
          end
        end
      end

      def build_module_entry(module_instance, explicit_label)
        {
          id: (module_instance.respond_to?(:module_scope_id) ? module_instance.module_scope_id : SecureRandom.uuid),
          class: module_instance.class.name,
          label: explicit_label || (module_instance.respond_to?(:module_scope_label) ? module_instance.module_scope_label : nil)
        }
      end
    end
  end
end
