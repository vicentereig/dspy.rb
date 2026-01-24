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
      # @param signature [DSPy::Signature, nil] Optional signature for structured outputs
      # @param block [Proc] Optional streaming block
      # @return [DSPy::LM::Response] Normalized response
      def chat(messages:, signature: nil, &block)
        raise NotImplementedError, "Subclasses must implement #chat method"
      end

      private

      def validate_configuration!
        raise ConfigurationError, "Model is required" if model.nil? || model.empty?
      end

      def validate_api_key!(api_key, provider)
        if api_key.nil? || api_key.to_s.strip.empty?
          raise MissingAPIKeyError.new(provider)
        end
      end

      # Helper method to normalize message format
      def normalize_messages(messages)
        messages.map do |msg|
          # Support both Message objects and hash format
          if msg.is_a?(DSPy::LM::Message)
            msg.to_h
          else
            content = msg[:content]
            # Don't convert array content to string
            {
              role: msg[:role].to_s,
              content: content.is_a?(Array) ? content : content.to_s
            }
          end
        end
      end
      
      # Check if messages contain images
      def contains_images?(messages)
        messages.any? do |msg|
          content = msg[:content] || msg.content
          content.is_a?(Array) && content.any? { |item| item[:type] == 'image' }
        end
      end

      # Format multimodal messages for a specific provider
      # @param messages [Array<Hash>] Array of message hashes
      # @param provider_name [String] Provider name for image validation and formatting
      # @return [Array<Hash>] Messages with images formatted for the provider
      def format_multimodal_messages(messages, provider_name)
        messages.map do |msg|
          if msg[:content].is_a?(Array)
            formatted_content = msg[:content].map do |item|
              case item[:type]
              when 'text'
                { type: 'text', text: item[:text] }
              when 'image'
                format_image_for_provider(item[:image], provider_name)
              else
                item
              end
            end
            { role: msg[:role], content: formatted_content }
          else
            msg
          end
        end
      end

      # Format an image for a specific provider
      # @param image [DSPy::Image] The image to format
      # @param provider_name [String] Provider name (openai, anthropic, gemini, etc.)
      # @return [Hash] Provider-specific image format
      def format_image_for_provider(image, provider_name)
        image.validate_for_provider!(provider_name)
        format_method = "to_#{provider_name}_format"
        if image.respond_to?(format_method)
          image.send(format_method)
        else
          # For providers without specific format methods, return the item as-is
          { type: 'image', image: image }
        end
      end
    end
  end
end
