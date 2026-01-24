# frozen_string_literal: true

require 'concurrent-ruby'
require 'thread'
require 'opentelemetry/sdk'
require 'opentelemetry/sdk/trace/export'

module DSPy
  class Observability
    # AsyncSpanProcessor provides non-blocking span export using concurrent-ruby.
    # Spans are queued and exported on a dedicated single-thread executor to avoid blocking clients.
    # Implements the same interface as OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor
    class AsyncSpanProcessor
      # Default configuration values
      DEFAULT_QUEUE_SIZE = 1000
      DEFAULT_EXPORT_INTERVAL = 60.0  # seconds
      DEFAULT_EXPORT_BATCH_SIZE = 100
      DEFAULT_SHUTDOWN_TIMEOUT = 10.0  # seconds
      DEFAULT_MAX_RETRIES = 3

      def initialize(
        exporter,
        queue_size: DEFAULT_QUEUE_SIZE,
        export_interval: DEFAULT_EXPORT_INTERVAL,
        export_batch_size: DEFAULT_EXPORT_BATCH_SIZE,
        shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
        max_retries: DEFAULT_MAX_RETRIES
      )
        @exporter = exporter
        @queue_size = queue_size
        @export_interval = export_interval
        @export_batch_size = export_batch_size
        @shutdown_timeout = shutdown_timeout
        @max_retries = max_retries
        @export_executor = Concurrent::SingleThreadExecutor.new

        # Use thread-safe queue for cross-fiber communication
        @queue = Thread::Queue.new
        @shutdown_requested = false
        @timer_thread = nil

        start_export_task
      end

      def on_start(span, parent_context)
        # Non-blocking - no operation needed on span start
      end

      def on_finish(span)
        # Only process sampled spans to match BatchSpanProcessor behavior
        return unless span.context.trace_flags.sampled?

        # Non-blocking enqueue with overflow protection
        # Note: on_finish is only called for already ended spans
        begin
          # Check queue size (non-blocking)
          if @queue.size >= @queue_size
            # Drop oldest span
            begin
              dropped_span = @queue.pop(true) # non-blocking pop
              DSPy.log('observability.span_dropped',
                       reason: 'queue_full',
                       queue_size: @queue_size)
            rescue ThreadError
              # Queue was empty, continue
            end
          end

          @queue.push(span)
          
          # Log span queuing activity
          DSPy.log('observability.span_queued', queue_size: @queue.size)

          # Trigger immediate export if batch size reached
          trigger_export_if_batch_full
        rescue StandardError => e
          DSPy.log('observability.enqueue_error', error: e.message)
        end
      end

      def shutdown(timeout: nil)
        timeout ||= @shutdown_timeout
        @shutdown_requested = true

        begin
          # Export any remaining spans
          result = export_remaining_spans(timeout: timeout, export_all: true)

          future = Concurrent::Promises.future_on(@export_executor) do
            @exporter.shutdown(timeout: timeout)
          end
          future.value!(timeout)

          result
        rescue StandardError => e
          DSPy.log('observability.shutdown_error', error: e.message, class: e.class.name)
          OpenTelemetry::SDK::Trace::Export::FAILURE
        ensure
          begin
            @timer_thread&.join(timeout)
            @timer_thread&.kill if @timer_thread&.alive?
          rescue StandardError
            # ignore timer shutdown issues
          end
          @export_executor.shutdown
          unless @export_executor.wait_for_termination(timeout)
            @export_executor.kill
          end
        end
      end

      def force_flush(timeout: nil)
        return OpenTelemetry::SDK::Trace::Export::SUCCESS if @queue.empty?

        export_remaining_spans(timeout: timeout, export_all: true)
      end

      private

      def start_export_task
        return if @export_interval <= 0 # Disable timer for testing
        return if ENV['DSPY_DISABLE_OBSERVABILITY'] == 'true' # Skip in tests

        @timer_thread = Thread.new do
          loop do
            break if @shutdown_requested

            sleep(@export_interval)
            break if @shutdown_requested
            next if @queue.empty?

            schedule_async_export(export_all: true)
          end
        rescue StandardError => e
          DSPy.log('observability.export_task_error', error: e.message, class: e.class.name)
        end
      end

      def trigger_export_if_batch_full
        return if @queue.size < @export_batch_size
        return if ENV['DSPY_DISABLE_OBSERVABILITY'] == 'true' # Skip in tests
        schedule_async_export(export_all: false)
      end

      def export_remaining_spans(timeout: nil, export_all: true)
        return OpenTelemetry::SDK::Trace::Export::SUCCESS if @queue.empty?

        future = Concurrent::Promises.future_on(@export_executor) do
          export_queued_spans_internal(export_all: export_all)
        end

        future.value!(timeout || @shutdown_timeout)
      rescue StandardError => e
        DSPy.log('observability.export_error', error: e.message, class: e.class.name)
        OpenTelemetry::SDK::Trace::Export::FAILURE
      end

      def schedule_async_export(export_all: false)
        return if @shutdown_requested

        @export_executor.post do
          export_queued_spans_internal(export_all: export_all)
        rescue StandardError => e
          DSPy.log('observability.batch_export_error', error: e.message, class: e.class.name)
        end
      end

      def export_queued_spans
        export_queued_spans_internal(export_all: false)
      end

      def export_queued_spans_internal(export_all: false)
        result = OpenTelemetry::SDK::Trace::Export::SUCCESS

        loop do
          spans = dequeue_spans(export_all ? @queue_size : @export_batch_size)
          break if spans.empty?

          result = export_spans_with_retry(spans)
          break if result == OpenTelemetry::SDK::Trace::Export::FAILURE

          break unless export_all || @queue.size >= @export_batch_size
        end

        result
      end

      def dequeue_spans(limit)
        spans = []

        limit.times do
          begin
            spans << @queue.pop(true) # non-blocking pop
          rescue ThreadError
            break
          end
        end

        spans
      end

      def export_spans_with_retry(spans)
        retries = 0

        # Convert spans to SpanData objects (required by OTLP exporter)
        span_data_batch = spans.map(&:to_span_data)
        
        # Log export attempt
        DSPy.log('observability.export_attempt',
                 spans_count: span_data_batch.size,
                 batch_size: span_data_batch.size)

        loop do
          result = @exporter.export(span_data_batch, timeout: @shutdown_timeout)

          case result
          when OpenTelemetry::SDK::Trace::Export::SUCCESS
            DSPy.log('observability.export_success',
                     spans_count: span_data_batch.size,
                     export_result: 'SUCCESS')
            return result
          when OpenTelemetry::SDK::Trace::Export::FAILURE
            retries += 1
            if retries <= @max_retries
              backoff_seconds = 0.1 * (2 ** retries)
              DSPy.log('observability.export_retry',
                       attempt: retries,
                       spans_count: span_data_batch.size,
                       backoff_seconds: backoff_seconds)
              # Exponential backoff
              sleep(backoff_seconds)
              next
            else
              DSPy.log('observability.export_failed',
                       spans_count: span_data_batch.size,
                       retries: retries)
              return result
            end
          else
            return result
          end
        end
      rescue StandardError => e
        DSPy.log('observability.export_error', error: e.message, class: e.class.name)
        OpenTelemetry::SDK::Trace::Export::FAILURE
      end

    end
  end
end
