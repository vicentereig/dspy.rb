# frozen_string_literal: true

require_relative 'sse_vcr'

# Monkey patch for Gemini client to integrate with SSE VCR
# This captures real streaming responses and replays them deterministically

# Hook into Gemini::Controllers::Client when it's loaded
module GeminiSSEHook
  def self.patch_gemini!
    return unless defined?(Gemini::Controllers::Client)
    return if Gemini::Controllers::Client.method_defined?(:sse_vcr_patched?)
    
    Gemini::Controllers::Client.class_eval do
      alias_method :original_stream_generate_content, :stream_generate_content
      
      def stream_generate_content(*args, &block)
        return original_stream_generate_content(*args, &block) unless SSEVCR.turned_on?

        request_signature = build_sse_vcr_signature(*args)
        cassette = SSEVCR.current_cassette
        
        if cassette.recording?
          # Record real streaming response
          chunks = []
          original_stream_generate_content(*args) do |chunk|
            chunks << chunk
            block&.call(chunk) if block
          end
          
          cassette.record_streaming_interaction(request_signature, chunks)
        else
          # Replay recorded streaming response
          interaction = cassette.find_matching_interaction(request_signature)
          
          if interaction
            # Handle string/symbol key differences
            response = interaction['response'] || interaction[:response]
            chunks = response['chunks'] || response[:chunks]
            chunks.each { |chunk| block&.call(chunk) } if block
          else
            raise "No matching SSE interaction found for #{request_signature[:uri]}"
          end
        end
      end

      def sse_vcr_patched?
        true
      end

      private

      def build_sse_vcr_signature(*args)
        params = args.first || {}
        base_uri = "#{@base_address}/#{@model_address}:streamGenerateContent"
        query_params = { alt: 'sse', key: '<GEMINI_API_KEY>' }
        
        {
          method: :post,
          uri: "#{base_uri}?#{query_params.map { |k, v| "#{k}=#{v}" }.join('&')}",
          body: params,
          headers: {
            'User-Agent' => 'Faraday v2.13.4',
            'Content-Type' => 'application/json',
            'Expect' => ''
          }
        }
      end

    end
  end
end

# Auto-patch when the gemini-ai gem is loaded
if defined?(Gemini::Controllers::Client)
  GeminiSSEHook.patch_gemini!
else
  # Hook into the require mechanism to patch when gemini-ai is loaded
  module Kernel
    alias_method :original_require, :require
    
    def require(name)
      result = original_require(name)
      if name == 'gemini-ai' || name.include?('gemini')
        GeminiSSEHook.patch_gemini!
      end
      result
    end
  end
end