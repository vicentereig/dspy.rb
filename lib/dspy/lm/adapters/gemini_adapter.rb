# frozen_string_literal: true

require 'gemini-ai'
require 'json'
require_relative '../vision_models'

module DSPy
  class LM
    class GeminiAdapter < Adapter
      def initialize(model:, api_key:, structured_outputs: false)
        super(model: model, api_key: api_key)
        validate_api_key!(api_key, 'gemini')
        
        @structured_outputs_enabled = structured_outputs
        
        @client = Gemini.new(
          credentials: {
            service: 'generative-language-api',
            api_key: api_key
          },
          options: { 
            model: model,
            server_sent_events: true
          }
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
          # Always use streaming
          content = ""
          final_response_data = nil
          
          @client.stream_generate_content(request_params) do |chunk|
            # Handle case where chunk might be a string (from SSE VCR)
            if chunk.is_a?(String)
              begin
                chunk = JSON.parse(chunk)
              rescue JSON::ParserError => e
                raise AdapterError, "Failed to parse Gemini streaming response: #{e.message}"
              end
            end
            
            # Extract content from chunks
            if chunk.dig('candidates', 0, 'content', 'parts')
              chunk_text = extract_text_from_parts(chunk.dig('candidates', 0, 'content', 'parts'))
              content += chunk_text
              
              # Call block only if provided (for real streaming)
              block.call(chunk) if block_given?
            end
            
            # Store final response data (usage, metadata) from last chunk
            if chunk['usageMetadata'] || chunk.dig('candidates', 0, 'finishReason')
              final_response_data = chunk
            end
          end
          
          # Extract usage information from final chunk
          usage_data = final_response_data&.dig('usageMetadata')
          usage_struct = usage_data ? UsageFactory.create('gemini', usage_data) : nil
          
          # Create metadata from final chunk
          metadata = {
            provider: 'gemini',
            model: model,
            finish_reason: final_response_data&.dig('candidates', 0, 'finishReason'),
            safety_ratings: final_response_data&.dig('candidates', 0, 'safetyRatings'),
            streaming: block_given?
          }
          
          # Create typed metadata
          typed_metadata = ResponseMetadataFactory.create('gemini', metadata)
          
          Response.new(
            content: content,
            usage: usage_struct,
            metadata: typed_metadata
          )
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