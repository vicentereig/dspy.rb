# frozen_string_literal: true

require 'openai'
require_relative 'openai/schema_converter'
require_relative '../vision_models'

module DSPy
  class LM
    class OpenAIAdapter < Adapter
      def initialize(model:, api_key:, structured_outputs: false)
        super(model: model, api_key: api_key)
        validate_api_key!(api_key, 'openai')
        @client = OpenAI::Client.new(api_key: api_key)
        @structured_outputs_enabled = structured_outputs
      end

      def chat(messages:, signature: nil, response_format: nil, &block)
        normalized_messages = normalize_messages(messages)
        
        # Validate vision support if images are present
        if contains_images?(normalized_messages)
          VisionModels.validate_vision_support!('openai', model)
          # Convert messages to OpenAI format with proper image handling
          normalized_messages = format_multimodal_messages(normalized_messages)
        end
        
        request_params = {
          model: model,
          messages: normalized_messages,
          temperature: 0.0 # DSPy default for deterministic responses
        }

        # Add response format if provided by strategy
        if response_format
          request_params[:response_format] = response_format
        elsif @structured_outputs_enabled && signature && supports_structured_outputs?
          # Legacy behavior for backward compatibility
          response_format = DSPy::LM::Adapters::OpenAI::SchemaConverter.to_openai_format(signature)
          request_params[:response_format] = response_format
        end

        # Add streaming if block provided
        if block_given?
          request_params[:stream] = proc do |chunk, _bytesize|
            block.call(chunk) if chunk.dig("choices", 0, "delta", "content")
          end
        end

        begin
          response = @client.chat.completions.create(**request_params)
          
          if response.respond_to?(:error) && response.error
            raise AdapterError, "OpenAI API error: #{response.error}"
          end

          choice = response.choices.first
          message = choice.message
          content = message.content
          usage = response.usage

          # Handle structured output refusals
          if message.respond_to?(:refusal) && message.refusal
            raise AdapterError, "OpenAI refused to generate output: #{message.refusal}"
          end

          # Convert usage data to typed struct
          usage_struct = UsageFactory.create('openai', usage)
          
          # Create typed metadata
          metadata = ResponseMetadataFactory.create('openai', {
            model: model,
            response_id: response.id,
            created: response.created,
            structured_output: @structured_outputs_enabled && signature && supports_structured_outputs?,
            system_fingerprint: response.system_fingerprint,
            finish_reason: choice.finish_reason
          })
          
          Response.new(
            content: content,
            usage: usage_struct,
            metadata: metadata
          )
        rescue => e
          # Check for specific error types and messages
          error_msg = e.message.to_s
          
          # Try to parse error body if it looks like JSON
          error_body = if error_msg.start_with?('{')
                         JSON.parse(error_msg) rescue nil
                       elsif e.respond_to?(:response) && e.response
                         e.response[:body] rescue nil
                       end
          
          # Check for specific image-related errors
          if error_msg.include?('image_parse_error') || error_msg.include?('unsupported image')
            raise AdapterError, "Image processing failed: #{error_msg}. Ensure your image is a valid PNG, JPEG, GIF, or WebP format and under 5MB."
          elsif error_msg.include?('rate') && error_msg.include?('limit')
            raise AdapterError, "OpenAI rate limit exceeded: #{error_msg}. Please wait and try again."
          elsif error_msg.include?('authentication') || error_msg.include?('API key') || error_msg.include?('Unauthorized')
            raise AdapterError, "OpenAI authentication failed: #{error_msg}. Check your API key."
          elsif error_body && error_body.dig('error', 'message')
            raise AdapterError, "OpenAI API error: #{error_body.dig('error', 'message')}"
          else
            # Generic error handling
            raise AdapterError, "OpenAI adapter error: #{e.message}"
          end
        end
      end

      private

      def supports_structured_outputs?
        DSPy::LM::Adapters::OpenAI::SchemaConverter.supports_structured_outputs?(model)
      end
      
      def format_multimodal_messages(messages)
        messages.map do |msg|
          if msg[:content].is_a?(Array)
            # Convert multimodal content to OpenAI format
            formatted_content = msg[:content].map do |item|
              case item[:type]
              when 'text'
                { type: 'text', text: item[:text] }
              when 'image'
                item[:image].to_openai_format
              else
                item
              end
            end
            
            {
              role: msg[:role],
              content: formatted_content
            }
          else
            msg
          end
        end
      end
    end
  end
end
