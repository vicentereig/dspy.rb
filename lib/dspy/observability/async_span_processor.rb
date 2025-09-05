# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'async/barrier'
require 'opentelemetry/sdk'
require 'opentelemetry/sdk/trace/export'

module DSPy
  class Observability
    # AsyncSpanProcessor provides truly non-blocking span export using Async gem.
    # Spans are queued and exported using async tasks with fiber-based concurrency.
    # Implements the same interface as OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor
    class AsyncSpanProcessor
      # Default configuration values
      DEFAULT_QUEUE_SIZE = 1000
      DEFAULT_EXPORT_INTERVAL = 5.0  # seconds
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

        # Use thread-safe queue for cross-fiber communication
        @queue = Thread::Queue.new
        @barrier = Async::Barrier.new
        @shutdown_requested = false
        @export_task = nil

        start_export_task
      end

      def on_start(span, parent_context)
        # Non-blocking - no operation needed on span start
      end

      def on_finish(span)
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
          
          # Trigger immediate export if batch size reached
          trigger_export_if_batch_full
        rescue => e
          DSPy.log('observability.enqueue_error', error: e.message)
        end
      end

      def shutdown(timeout: nil)
        timeout ||= @shutdown_timeout
        @shutdown_requested = true

        begin
          # Export any remaining spans
          export_remaining_spans
          
          # Shutdown exporter
          @exporter.shutdown(timeout: timeout)
          
          OpenTelemetry::SDK::Trace::Export::SUCCESS
        rescue => e
          DSPy.log('observability.shutdown_error', error: e.message, class: e.class.name)
          OpenTelemetry::SDK::Trace::Export::FAILURE
        end
      end

      def force_flush(timeout: nil)
        return OpenTelemetry::SDK::Trace::Export::SUCCESS if @queue.empty?

        export_remaining_spans
      end

      private

      def start_export_task
        return if @export_interval <= 0 # Disable timer for testing

        # Start timer-based export task in background
        Thread.new do
          loop do
            break if @shutdown_requested
            
            sleep(@export_interval)
            
            # Export queued spans in sync block
            unless @queue.empty?
              Sync do
                export_queued_spans
              end
            end
          end
        rescue => e
          DSPy.log('observability.export_task_error', error: e.message, class: e.class.name)
        end
      end

      def trigger_export_if_batch_full
        return if @queue.size < @export_batch_size

        # Trigger immediate export in background
        Thread.new do
          Sync do
            export_queued_spans
          end
        rescue => e
          DSPy.log('observability.batch_export_error', error: e.message)
        end
      end

      def export_remaining_spans
        spans = []
        
        # Drain entire queue
        until @queue.empty?
          begin
            spans << @queue.pop(true) # non-blocking pop
          rescue ThreadError
            break
          end
        end

        return OpenTelemetry::SDK::Trace::Export::SUCCESS if spans.empty?

        export_spans_with_retry(spans)
      end

      def export_queued_spans
        spans = []
        
        # Collect up to batch size
        @export_batch_size.times do
          begin
            spans << @queue.pop(true) # non-blocking pop
          rescue ThreadError
            break
          end
        end

        return if spans.empty?

        # Export using async I/O
        Sync do
          export_spans_with_retry_async(spans)
        end
      end

      def export_spans_with_retry(spans)
        retries = 0
        
        loop do
          result = @exporter.export(spans, timeout: @shutdown_timeout)
          
          case result
          when OpenTelemetry::SDK::Trace::Export::SUCCESS
            return result
          when OpenTelemetry::SDK::Trace::Export::FAILURE
            retries += 1
            if retries <= @max_retries
              # Exponential backoff
              sleep(0.1 * (2 ** retries))
              next
            else
              DSPy.log('observability.export_failed',
                       spans_count: spans.size,
                       retries: retries)
              return result
            end
          else
            return result
          end
        end
      rescue => e
        DSPy.log('observability.export_error', error: e.message, class: e.class.name)
        OpenTelemetry::SDK::Trace::Export::FAILURE
      end

      def export_spans_with_retry_async(spans)
        retries = 0
        
        loop do
          # Use current async task for potentially non-blocking export
          result = @exporter.export(spans, timeout: @shutdown_timeout)
          
          case result
          when OpenTelemetry::SDK::Trace::Export::SUCCESS
            return result
          when OpenTelemetry::SDK::Trace::Export::FAILURE
            retries += 1
            if retries <= @max_retries
              # Async sleep for exponential backoff
              Async::Task.current.sleep(0.1 * (2 ** retries))
              next
            else
              DSPy.log('observability.export_failed',
                       spans_count: spans.size,
                       retries: retries)
              return result
            end
          else
            return result
          end
        end
      rescue => e
        DSPy.log('observability.export_error', error: e.message, class: e.class.name)
        OpenTelemetry::SDK::Trace::Export::FAILURE
      end
    end
  end
end