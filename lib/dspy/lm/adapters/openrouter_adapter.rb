# frozen_string_literal: true

require 'openai'

module DSPy
  class LM
    class OpenrouterAdapter < OpenAIAdapter
      BASE_URL = 'https://openrouter.ai/api/v1'

      def initialize(model:, api_key: nil, structured_outputs: true, http_referrer: nil, x_title: nil)
        # Don't call parent's initialize, do it manually to control client creation
        @model = model
        @api_key = api_key
        @structured_outputs_enabled = structured_outputs


        @http_referrer = http_referrer
        @x_title = x_title

        validate_configuration!

        # Create client with custom base URL
        @client = OpenAI::Client.new(
          api_key: @api_key,
          base_url: BASE_URL
        )
      end

      def chat(messages:, signature: nil, response_format: nil, &block)
        # For OpenRouter, we need to be more lenient with structured outputs
        # as the model behind it may not fully support OpenAI's response_format spec
        begin
          super
        rescue => e
          # If structured output fails, retry with enhanced prompting
          if @structured_outputs_enabled && signature && e.message.include?('response_format')
            DSPy.logger.debug("OpenRouter structured output failed, falling back to enhanced prompting")
            @structured_outputs_enabled = false
            retry
          else
            raise
          end
        end
      end

      protected

      # Add any OpenRouter-specific headers to all requests
      def default_request_params
        headers = {
          'X-Title' => @x_title,
          'HTTP-Referer' => @http_referrer
        }.compact

        upstream_params = super
        upstream_params.merge!(request_options: { extra_headers: headers }) if headers.any?
        upstream_params
      end

      private

      def supports_structured_outputs?
        # Different models behind OpenRouter may have different capabilities
        # For now, we rely on whatever was passed to the constructor
        @structured_outputs_enabled
      end
    end
  end
end
