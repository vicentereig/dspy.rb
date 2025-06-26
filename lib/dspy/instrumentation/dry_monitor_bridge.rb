# frozen_string_literal: true

require 'dry-monitor'

module DSPy
  module Instrumentation
    # Bridge DSPy events to dry-monitor's HTTP instrumentation plugin
    # Enables automatic HTTP request tracking for LLM API calls
    class DryMonitorBridge
      def self.setup!
        return unless DSPy::Instrumentation.config.enabled

        # Enable HTTP plugin for automatic request instrumentation
        monitor = Dry::Monitor::Notifications.new(:http)
        
        # Subscribe to HTTP events and map to DSPy LM events
        monitor.subscribe('http.request') do |event|
          # Only track LLM provider requests
          if llm_provider_request?(event[:uri])
            payload = {
              server_address: event[:uri].host,
              server_port: event[:uri].port,
              http_status_code: event[:status],
              http_method: event[:method],
              duration_ms: event[:time]&.*(1000)&.round(2)
            }

            DSPy::Instrumentation.emit('dspy.lm.http_request', payload)
          end
        end

        monitor
      end

      private

      def self.llm_provider_request?(uri)
        return false unless uri

        llm_hosts = [
          'api.openai.com',
          'api.anthropic.com',
          'api.cohere.ai',
          'generativelanguage.googleapis.com'
        ]

        llm_hosts.any? { |host| uri.host&.include?(host) }
      end
    end
  end
end
