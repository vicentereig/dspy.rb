# frozen_string_literal: true

module DSPy
  class LM
    # Base adapter interface for all LM providers
    class Adapter
      attr_reader :model, :api_key

      def initialize(model:, api_key:)
        @model = model
        @api_key = api_key
        validate_configuration!
      end

      # Chat interface that all adapters must implement
      # @param messages [Array<Hash>] Array of message hashes with :role and :content
      # @param block [Proc] Optional streaming block
      # @return [DSPy::LM::Response] Normalized response
      def chat(messages:, &block)
        raise NotImplementedError, "Subclasses must implement #chat method"
      end

      private

      def validate_configuration!
        raise ConfigurationError, "Model is required" if model.nil? || model.empty?
        raise ConfigurationError, "API key is required" if api_key.nil? || api_key.empty?
      end

      # Helper method to normalize message format
      def normalize_messages(messages)
        messages.map do |msg|
          {
            role: msg[:role].to_s,
            content: msg[:content].to_s
          }
        end
      end
    end
  end
end
