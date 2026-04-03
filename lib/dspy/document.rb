# frozen_string_literal: true

require 'base64'
require 'stringio'
require 'uri'

module DSPy
  class Document
    class RubyLLMInlineAttachment < StringIO
      attr_reader :path

      def initialize(content, path:)
        super(content)
        @path = path
        binmode
      end
    end

    private_constant :RubyLLMInlineAttachment

    attr_reader :url, :base64, :data, :content_type

    SUPPORTED_FORMATS = %w[application/pdf].freeze
    MAX_SIZE_BYTES = 32 * 1024 * 1024 # 32MB limit

    def initialize(url: nil, base64: nil, data: nil, content_type: nil)
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
      raise DSPy::LM::IncompatibleDocumentFeatureError,
            "OpenAI document inputs are not supported in this release. Use Anthropic directly or Anthropic via RubyLLM."
    end

    def to_anthropic_format
      if url
        {
          type: 'document',
          source: {
            type: 'url',
            url: url
          }
        }
      else
        {
          type: 'document',
          source: {
            type: 'base64',
            media_type: content_type,
            data: to_base64
          }
        }
      end
    end

    def to_gemini_format
      raise DSPy::LM::IncompatibleDocumentFeatureError,
            "Gemini document inputs are not supported in this release. Use Anthropic directly or Anthropic via RubyLLM."
    end

    def to_ruby_llm_attachment
      if url
        url
      else
        RubyLLMInlineAttachment.new(to_binary, path: 'document.pdf')
      end
    end

    def to_base64
      return base64 if base64
      return Base64.strict_encode64(data.pack('C*')) if data

      nil
    end

    def validate_for_provider!(provider)
      case provider
      when 'anthropic'
        true
      when 'openai'
        raise DSPy::LM::IncompatibleDocumentFeatureError,
              "OpenAI document inputs are not supported in this release. Use Anthropic directly or Anthropic via RubyLLM."
      when 'gemini'
        raise DSPy::LM::IncompatibleDocumentFeatureError,
              "Gemini document inputs are not supported in this release. Use Anthropic directly or Anthropic via RubyLLM."
      else
        raise DSPy::LM::IncompatibleDocumentFeatureError,
              "Unknown provider '#{provider}'. Document inputs are currently supported only for Anthropic."
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
        raise ArgumentError, "Unsupported document format: #{content_type}. Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
      end
    end

    def validate_size!(size_bytes)
      if size_bytes > MAX_SIZE_BYTES
        raise ArgumentError, "Document size exceeds 32MB limit (got #{size_bytes} bytes)"
      end
    end

    def infer_content_type_from_url(url)
      extension = File.extname(URI.parse(url).path).downcase

      case extension
      when '.pdf'
        'application/pdf'
      else
        raise ArgumentError, "Document URL must point to a PDF (.pdf): #{url}"
      end
    end

    def to_binary
      return Base64.decode64(base64) if base64
      return data.pack('C*') if data

      raise ArgumentError, "Document has no binary content"
    end
  end
end
