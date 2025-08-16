# frozen_string_literal: true

require 'gemini-ai'
require 'json'
require_relative '../vision_models'

module DSPy
  class LM
    class GeminiAdapter < Adapter
      def initialize(model:, api_key:)
        super
        validate_api_key!(api_key, 'gemini')
        
        # Create two clients - one for streaming, one for regular calls
        @base_credentials = {
          service: 'generative-language-api',
          api_key: api_key
        }
        @base_options = { model: model }
        
        @client = Gemini.new(
          credentials: @base_credentials,
          options: @base_options
        )
        
        @streaming_client = Gemini.new(
          credentials: @base_credentials,
          options: @base_options.merge(server_sent_events: true)
        )
      end

      def chat(messages:, signature: nil, **extra_params, &block)
        normalized_messages = normalize_messages(messages)
        
        # Validate vision support if images are present
        if contains_images?(normalized_messages)
          VisionModels.validate_vision_support!('gemini', model)
          # Convert messages to Gemini format with proper image handling
          normalized_messages = format_multimodal_messages(normalized_messages)
        end
        
        # Convert DSPy message format to Gemini format
        gemini_messages = convert_messages_to_gemini_format(normalized_messages)
        
        request_params = {
          contents: gemini_messages
        }.merge(extra_params)

        begin
          if block_given?
            # Streaming response
            content = ""
            @streaming_client.stream_generate_content(request_params) do |chunk|
              # Handle case where chunk might be a string (from VCR)
              if chunk.is_a?(String)
                begin
                  chunk = JSON.parse(chunk)
                rescue JSON::ParserError => e
                  raise AdapterError, "Failed to parse Gemini streaming response: #{e.message}"
                end
              end
              
              if chunk.dig('candidates', 0, 'content', 'parts')
                chunk_text = extract_text_from_parts(chunk.dig('candidates', 0, 'content', 'parts'))
                content += chunk_text
                block.call(chunk)
              end
            end
            
            # Create typed metadata for streaming response
            metadata = ResponseMetadataFactory.create('gemini', {
              model: model,
              streaming: true
            })
            
            Response.new(
              content: content,
              usage: nil, # Usage not available in streaming
              metadata: metadata
            )
          else
            response = @client.generate_content(request_params)
            
            # Handle case where response might be a string (from VCR)
            if response.is_a?(String)
              begin
                response = JSON.parse(response)
              rescue JSON::ParserError => e
                raise AdapterError, "Failed to parse Gemini response: #{e.message}"
              end
            end
            
            # Extract content from response
            content = ""
            if response.dig('candidates', 0, 'content', 'parts')
              content = extract_text_from_parts(response.dig('candidates', 0, 'content', 'parts'))
            end
            
            # Extract usage information
            usage_data = response['usageMetadata']
            usage_struct = UsageFactory.create('gemini', usage_data)
            
            # Create metadata
            metadata = {
              provider: 'gemini',
              model: model,
              finish_reason: response.dig('candidates', 0, 'finishReason'),
              safety_ratings: response.dig('candidates', 0, 'safetyRatings')
            }
            
            # Create typed metadata
            typed_metadata = ResponseMetadataFactory.create('gemini', metadata)
            
            Response.new(
              content: content,
              usage: usage_struct,
              metadata: typed_metadata
            )
          end
        rescue => e
          handle_gemini_error(e)
        end
      end

      private

      # Convert DSPy message format to Gemini format
      def convert_messages_to_gemini_format(messages)
        # Gemini expects contents array with role and parts
        messages.map do |msg|
          role = case msg[:role]
                 when 'system'
                   'user' # Gemini doesn't have explicit system role, merge with user
                 when 'assistant'
                   'model'
                 else
                   msg[:role]
                 end
          
          if msg[:content].is_a?(Array)
            # Multimodal content
            parts = msg[:content].map do |item|
              case item[:type]
              when 'text'
                { text: item[:text] }
              when 'image'
                item[:image].to_gemini_format
              else
                item
              end
            end
            
            { role: role, parts: parts }
          else
            # Text-only content
            { role: role, parts: [{ text: msg[:content] }] }
          end
        end
      end
      
      # Extract text content from Gemini parts array
      def extract_text_from_parts(parts)
        return "" unless parts.is_a?(Array)
        
        parts.map { |part| part['text'] }.compact.join
      end
      
      # Format multimodal messages for Gemini
      def format_multimodal_messages(messages)
        messages.map do |msg|
          if msg[:content].is_a?(Array)
            # Convert multimodal content to Gemini format
            formatted_content = msg[:content].map do |item|
              case item[:type]
              when 'text'
                { type: 'text', text: item[:text] }
              when 'image'
                # Validate image compatibility before formatting
                item[:image].validate_for_provider!('gemini')
                item[:image].to_gemini_format
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
      
      # Handle Gemini-specific errors
      def handle_gemini_error(error)
        error_msg = error.message.to_s
        
        if error_msg.include?('API_KEY') || error_msg.include?('status 400') || error_msg.include?('status 401') || error_msg.include?('status 403')
          raise AdapterError, "Gemini authentication failed: #{error_msg}. Check your API key."
        elsif error_msg.include?('RATE_LIMIT') || error_msg.downcase.include?('quota') || error_msg.include?('status 429')
          raise AdapterError, "Gemini rate limit exceeded: #{error_msg}. Please wait and try again."
        elsif error_msg.include?('SAFETY') || error_msg.include?('blocked')
          raise AdapterError, "Gemini content was blocked by safety filters: #{error_msg}"
        elsif error_msg.include?('image') || error_msg.include?('media')
          raise AdapterError, "Gemini image processing failed: #{error_msg}. Ensure your image is a valid format and under size limits."
        else
          # Generic error handling
          raise AdapterError, "Gemini adapter error: #{error_msg}"
        end
      end
    end
  end
end