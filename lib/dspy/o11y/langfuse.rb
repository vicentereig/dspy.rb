# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'openssl'
require 'dspy/o11y'
require_relative 'langfuse/version'

module DSPy
  class Observability
    module Adapters
      module Langfuse
        module_function

        def register!
          DSPy::Observability.register_configurator(:langfuse) do |obs|
            configure(obs)
          end
        end

        def configure(obs)
          return obs.disable!(reason: 'Explicitly disabled via DSPY_DISABLE_OBSERVABILITY') if ENV['DSPY_DISABLE_OBSERVABILITY'] == 'true'

          public_key = ENV['LANGFUSE_PUBLIC_KEY']
          secret_key = ENV['LANGFUSE_SECRET_KEY']

          if test_environment? && !(public_key && secret_key)
            return obs.disable!(reason: 'Test environment detected - OTLP disabled')
          end

          return false unless public_key && secret_key

          require_opentelemetry!
          patch_frozen_ssl_context_for_otlp!

          endpoint = langfuse_endpoint
          auth_string = Base64.strict_encode64("#{public_key}:#{secret_key}")

          OpenTelemetry::SDK.configure do |config|
            config.service_name = 'dspy-ruby'
            config.service_version = DSPy::VERSION

            exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
              endpoint: endpoint,
              headers: {
                'Authorization' => "Basic #{auth_string}",
                'Content-Type' => 'application/x-protobuf'
              },
              compression: 'gzip'
            )

            async_config = {
              queue_size: (ENV['DSPY_TELEMETRY_QUEUE_SIZE'] || DSPy::Observability::AsyncSpanProcessor::DEFAULT_QUEUE_SIZE).to_i,
              export_interval: (ENV['DSPY_TELEMETRY_EXPORT_INTERVAL'] || DSPy::Observability::AsyncSpanProcessor::DEFAULT_EXPORT_INTERVAL).to_f,
              export_batch_size: (ENV['DSPY_TELEMETRY_BATCH_SIZE'] || DSPy::Observability::AsyncSpanProcessor::DEFAULT_EXPORT_BATCH_SIZE).to_i,
              shutdown_timeout: (ENV['DSPY_TELEMETRY_SHUTDOWN_TIMEOUT'] || DSPy::Observability::AsyncSpanProcessor::DEFAULT_SHUTDOWN_TIMEOUT).to_f
            }

            config.add_span_processor(
              DSPy::Observability::AsyncSpanProcessor.new(exporter, **async_config)
            )

            config.resource = OpenTelemetry::SDK::Resources::Resource.create({
              'service.name' => 'dspy-ruby',
              'service.version' => DSPy::VERSION,
              'telemetry.sdk.name' => 'opentelemetry',
              'telemetry.sdk.language' => 'ruby'
            })
          end

          tracer = OpenTelemetry.tracer_provider.tracer('dspy', DSPy::VERSION)
          obs.enable!(tracer: tracer, endpoint: endpoint)
          true
        rescue LoadError
          obs.disable!(reason: 'OpenTelemetry gems not available')
          false
        rescue StandardError => e
          DSPy.log('observability.error', error: e.message, adapter: 'langfuse', class: e.class.name)
          obs.disable!
          false
        end

        def test_environment?
          ENV['RACK_ENV'] == 'test' || ENV['RAILS_ENV'] == 'test' || defined?(RSpec)
        end
        private_class_method :test_environment?

        def require_opentelemetry!
          DSPy::Observability.require_dependency('opentelemetry/sdk')
          DSPy::Observability.require_dependency('opentelemetry/exporter/otlp')
        end
        private_class_method :require_opentelemetry!

        def langfuse_endpoint
          host = ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
          "#{host}/api/public/otel/v1/traces"
        end
        private_class_method :langfuse_endpoint

        def patch_frozen_ssl_context_for_otlp!
          return unless defined?(OpenTelemetry::Exporter::OTLP::Exporter)

          exporter = OpenTelemetry::Exporter::OTLP::Exporter
          keep_alive_timeout = exporter.const_get(:KEEP_ALIVE_TIMEOUT)
          return if exporter.instance_variable_defined?(:@_dspy_ssl_patch_applied)

          exporter.class_eval do
            define_method(:http_connection) do |uri, ssl_verify_mode, certificate_file, client_certificate_file, client_key_file|
              http = Net::HTTP.new(uri.host, uri.port)
              use_ssl = uri.scheme == 'https'
              http.use_ssl = use_ssl

              if use_ssl && http.respond_to?(:ssl_context) && http.ssl_context&.frozen?
                http.instance_variable_set(:@ssl_context, OpenSSL::SSL::SSLContext.new)
              end

              http.verify_mode = ssl_verify_mode
              http.ca_file = certificate_file unless certificate_file.nil?
              http.cert = OpenSSL::X509::Certificate.new(File.read(client_certificate_file)) unless client_certificate_file.nil?
              http.key = OpenSSL::PKey::RSA.new(File.read(client_key_file)) unless client_key_file.nil?
              http.keep_alive_timeout = keep_alive_timeout
              http
            end
          end

          exporter.instance_variable_set(:@_dspy_ssl_patch_applied, true)
        end
        private_class_method :patch_frozen_ssl_context_for_otlp!
      end
    end
  end
end

DSPy::Observability::Adapters::Langfuse.register!

# Load scores exporter for Langfuse
require_relative 'langfuse/scores_exporter'
