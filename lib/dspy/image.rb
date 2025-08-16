# frozen_string_literal: true

require 'base64'
require 'uri'

module DSPy
  class Image
    attr_reader :url, :base64, :data, :content_type, :detail
    
    SUPPORTED_FORMATS = %w[image/jpeg image/png image/gif image/webp].freeze
    MAX_SIZE_BYTES = 5 * 1024 * 1024 # 5MB limit
    
    # Provider capability registry
    PROVIDER_CAPABILITIES = {
      'openai' => {
        sources: %w[url base64 data],
        parameters: %w[detail]
      },
      'anthropic' => {
        sources: %w[base64 data], 
        parameters: []
      },
      'gemini' => {
        sources: %w[base64 data], # Gemini supports inline base64 data, not URLs
        parameters: []
      }
    }.freeze
    
    def initialize(url: nil, base64: nil, data: nil, content_type: nil, detail: nil)
      @detail = detail # OpenAI detail level: 'low', 'high', or 'auto'
      
      # Validate input
      validate_input!(url, base64, data)
      
      if url
        @url = url
        @content_type = content_type || infer_content_type_from_url(url)
      elsif base64
        raise ArgumentError, "content_type is required when using base64" unless content_type
        @base64 = base64
        @content_type = content_type
        validate_size!(Base64.decode64(base64).bytesize)
      elsif data
        raise ArgumentError, "content_type is required when using data" unless content_type
        @data = data
        @content_type = content_type
        validate_size!(data.size)
      end
      
      validate_content_type!
    end
    
    def to_openai_format
      if url
        format = {
          type: 'image_url',
          image_url: {
            url: url
          }
        }
        format[:image_url][:detail] = detail if detail
        format
      elsif base64
        {
          type: 'image_url',
          image_url: {
            url: "data:#{content_type};base64,#{base64}"
          }
        }
      elsif data
        {
          type: 'image_url',
          image_url: {
            url: "data:#{content_type};base64,#{to_base64}"
          }
        }
      end
    end
    
    def to_anthropic_format
      if url
        # Anthropic requires base64, so we'd need to fetch the URL
        # For now, we'll raise an error or skip
        raise NotImplementedError, "URL fetching for Anthropic not yet implemented"
      elsif base64
        {
          type: 'image',
          source: {
            type: 'base64',
            media_type: content_type,
            data: base64
          }
        }
      elsif data
        {
          type: 'image',
          source: {
            type: 'base64',
            media_type: content_type,
            data: to_base64
          }
        }
      end
    end
    
    def to_gemini_format
      if url
        # Gemini requires base64 for inline data, URLs not supported for inline_data
        raise NotImplementedError, "URL fetching for Gemini not yet implemented. Use base64 or data instead."
      elsif base64
        {
          inline_data: {
            mime_type: content_type,
            data: base64
          }
        }
      elsif data
        {
          inline_data: {
            mime_type: content_type,
            data: to_base64
          }
        }
      end
    end
    
    def to_base64
      return base64 if base64
      return Base64.strict_encode64(data.pack('C*')) if data
      nil
    end
    
    def validate!
      validate_content_type!
      
      if base64
        validate_size!(Base64.decode64(base64).bytesize)
      elsif data
        validate_size!(data.size)
      end
    end
    
    def validate_for_provider!(provider)
      capabilities = PROVIDER_CAPABILITIES[provider]
      
      unless capabilities
        raise DSPy::LM::IncompatibleImageFeatureError, 
              "Unknown provider '#{provider}'. Supported providers: #{PROVIDER_CAPABILITIES.keys.join(', ')}"
      end
      
      # Check source compatibility
      current_source = if url
                         'url'
                       elsif base64
                         'base64'
                       elsif data
                         'data'
                       end
      
      unless capabilities[:sources].include?(current_source)
        case provider
        when 'anthropic'
          if current_source == 'url'
            raise DSPy::LM::IncompatibleImageFeatureError,
                  "Anthropic doesn't support image URLs. Please provide base64 or raw data instead."
          end
        when 'gemini'
          if current_source == 'url'
            raise DSPy::LM::IncompatibleImageFeatureError,
                  "Gemini doesn't support image URLs for inline data. Please provide base64 or raw data instead."
          end
        end
      end
      
      # Check parameter compatibility
      if detail && !capabilities[:parameters].include?('detail')
        case provider
        when 'anthropic'
          raise DSPy::LM::IncompatibleImageFeatureError,
                "Anthropic doesn't support the 'detail' parameter. This feature is OpenAI-specific."
        when 'gemini'
          raise DSPy::LM::IncompatibleImageFeatureError,
                "Gemini doesn't support the 'detail' parameter. This feature is OpenAI-specific."
        end
      end
    end
    
    private
    
    def validate_input!(url, base64, data)
      inputs = [url, base64, data].compact
      
      if inputs.empty?
        raise ArgumentError, "Must provide either url, base64, or data"
      elsif inputs.size > 1
        raise ArgumentError, "Only one of url, base64, or data can be provided"
      end
    end
    
    def validate_content_type!
      unless SUPPORTED_FORMATS.include?(content_type)
        raise ArgumentError, "Unsupported image format: #{content_type}. Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
      end
    end
    
    def validate_size!(size_bytes)
      if size_bytes > MAX_SIZE_BYTES
        raise ArgumentError, "Image size exceeds 5MB limit (got #{size_bytes} bytes)"
      end
    end
    
    def infer_content_type_from_url(url)
      extension = File.extname(URI.parse(url).path).downcase
      
      case extension
      when '.jpg', '.jpeg'
        'image/jpeg'
      when '.png'
        'image/png'
      when '.gif'
        'image/gif'
      when '.webp'
        'image/webp'
      else
        'image/jpeg' # Default fallback
      end
    end
  end
end