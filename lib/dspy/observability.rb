# frozen_string_literal: true

require 'base64'

module DSPy
  class Observability
    class << self
      attr_reader :enabled, :tracer, :endpoint

      def configure!
        @enabled = false
        
        # Check for required Langfuse environment variables
        public_key = ENV['LANGFUSE_PUBLIC_KEY']
        secret_key = ENV['LANGFUSE_SECRET_KEY']
        
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
            
            # Add OTLP exporter for Langfuse
            config.add_span_processor(
              OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
                OpenTelemetry::Exporter::OTLP::Exporter.new(
                  endpoint: @endpoint,
                  headers: {
                    'Authorization' => "Basic #{auth_string}",
                    'Content-Type' => 'application/x-protobuf'
                  },
                  compression: 'gzip'
                )
              )
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

      def reset!
        @enabled = false
        @tracer = nil
        @endpoint = nil
      end
    end
  end
end