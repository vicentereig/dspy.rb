# frozen_string_literal: true

require 'base64'
require_relative 'observability/async_span_processor'

module DSPy
  class Observability
    class << self
      attr_reader :enabled, :tracer, :endpoint

      def configure!
        @enabled = false
        
        # Check for explicit disable flag first
        if ENV['DSPY_DISABLE_OBSERVABILITY'] == 'true'
          DSPy.log('observability.disabled', reason: 'Explicitly disabled via DSPY_DISABLE_OBSERVABILITY')
          return
        end
        
        # Check for required Langfuse environment variables
        public_key = ENV['LANGFUSE_PUBLIC_KEY']
        secret_key = ENV['LANGFUSE_SECRET_KEY']
        
        # Skip OTLP configuration in test environment UNLESS Langfuse credentials are explicitly provided
        # This allows observability tests to run while protecting general tests from network calls
        if (ENV['RACK_ENV'] == 'test' || ENV['RAILS_ENV'] == 'test' || defined?(RSpec)) && !(public_key && secret_key)
          DSPy.log('observability.disabled', reason: 'Test environment detected - OTLP disabled')
          return
        end
        
        unless public_key && secret_key
          return
        end

        # Determine endpoint based on host
        host = ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
        @endpoint = "#{host}/api/public/otel/v1/traces"

        begin
          # Load OpenTelemetry gems
          require 'opentelemetry/sdk'
          require 'opentelemetry/exporter/otlp'

          # Generate Basic Auth header
          auth_string = Base64.strict_encode64("#{public_key}:#{secret_key}")
          
          # Configure OpenTelemetry SDK
          OpenTelemetry::SDK.configure do |config|
            config.service_name = 'dspy-ruby'
            config.service_version = DSPy::VERSION
            
            # Add OTLP exporter for Langfuse using AsyncSpanProcessor
            exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
              endpoint: @endpoint,
              headers: {
                'Authorization' => "Basic #{auth_string}",
                'Content-Type' => 'application/x-protobuf'
              },
              compression: 'gzip'
            )
            
            # Configure AsyncSpanProcessor with environment variables
            async_config = {
              queue_size: (ENV['DSPY_TELEMETRY_QUEUE_SIZE'] || AsyncSpanProcessor::DEFAULT_QUEUE_SIZE).to_i,
              export_interval: (ENV['DSPY_TELEMETRY_EXPORT_INTERVAL'] || AsyncSpanProcessor::DEFAULT_EXPORT_INTERVAL).to_f,
              export_batch_size: (ENV['DSPY_TELEMETRY_BATCH_SIZE'] || AsyncSpanProcessor::DEFAULT_EXPORT_BATCH_SIZE).to_i,
              shutdown_timeout: (ENV['DSPY_TELEMETRY_SHUTDOWN_TIMEOUT'] || AsyncSpanProcessor::DEFAULT_SHUTDOWN_TIMEOUT).to_f
            }
            
            config.add_span_processor(
              AsyncSpanProcessor.new(exporter, **async_config)
            )
            
            # Add resource attributes
            config.resource = OpenTelemetry::SDK::Resources::Resource.create({
              'service.name' => 'dspy-ruby',
              'service.version' => DSPy::VERSION,
              'telemetry.sdk.name' => 'opentelemetry',
              'telemetry.sdk.language' => 'ruby'
            })
          end

          # Create tracer
          @tracer = OpenTelemetry.tracer_provider.tracer('dspy', DSPy::VERSION)
          @enabled = true

        rescue LoadError => e
          DSPy.log('observability.disabled', reason: 'OpenTelemetry gems not available')
        rescue StandardError => e
          DSPy.log('observability.error', error: e.message, class: e.class.name)
        end
      end

      def enabled?
        @enabled == true
      end

      def tracer
        @tracer
      end

      def start_span(operation_name, attributes = {})
        return nil unless enabled? && tracer

        # Convert attribute keys to strings and filter out nil values
        string_attributes = attributes.transform_keys(&:to_s)
                                     .reject { |k, v| v.nil? }
        string_attributes['operation.name'] = operation_name
        
        tracer.start_span(
          operation_name,
          kind: :internal,
          attributes: string_attributes
        )
      rescue StandardError => e
        DSPy.log('observability.span_error', error: e.message, operation: operation_name)
        nil
      end

      def finish_span(span)
        return unless span
        
        span.finish
      rescue StandardError => e
        DSPy.log('observability.span_finish_error', error: e.message)
      end

      def flush!
        return unless enabled?
        
        # Force flush any pending spans
        OpenTelemetry.tracer_provider.force_flush
      rescue StandardError => e
        DSPy.log('observability.flush_error', error: e.message)
      end

      def reset!
        @enabled = false
        
        # Shutdown OpenTelemetry if it's configured
        if defined?(OpenTelemetry) && OpenTelemetry.tracer_provider
          begin
            OpenTelemetry.tracer_provider.shutdown(timeout: 1.0)
          rescue => e
            # Ignore shutdown errors in tests - log them but don't fail
            DSPy.log('observability.shutdown_error', error: e.message) if respond_to?(:log)
          end
        end
        
        @tracer = nil
        @endpoint = nil
      end
    end
  end
end