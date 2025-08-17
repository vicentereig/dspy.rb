# frozen_string_literal: true

require 'json'
require 'fileutils'

# SSE VCR - A VCR-like system for Server-Sent Events streaming
# Records real SSE streams to disk and replays them for deterministic tests
module SSEVCR
  class Configuration
    attr_accessor :cassette_library_dir, :hook_into, :filter_sensitive_data

    def initialize
      @cassette_library_dir = 'spec/sse_cassettes'
      @hook_into = []
      @filter_sensitive_data = {}
    end
  end

  class << self
    attr_accessor :configuration, :current_cassette

    def configure
      self.configuration ||= Configuration.new
      yield(configuration) if block_given?
    end

    def use_cassette(name, options = {}, &block)
      cassette = Cassette.new(name, options)
      self.current_cassette = cassette
      
      begin
        cassette.eject if cassette.recording?
        result = block.call
        cassette.save if cassette.recording?
        result
      ensure
        self.current_cassette = nil
      end
    end

    def recording?
      current_cassette&.recording?
    end

    def turned_on?
      !current_cassette.nil?
    end
  end

  class Cassette
    attr_reader :name, :options, :interactions

    def initialize(name, options = {})
      @name = name
      @options = options
      @interactions = []
      @cassette_path = File.join(SSEVCR.configuration.cassette_library_dir, "#{name}.json")
      
      load_existing_cassette
    end

    def recording?
      !File.exist?(@cassette_path) || @options[:record] == :all
    end

    def record_streaming_interaction(request_signature, chunks)
      interaction = {
        request: serialize_request(request_signature),
        response: {
          chunks: chunks.map { |chunk| filter_sensitive_data(chunk) },
          recorded_at: Time.now.iso8601
        }
      }
      @interactions << interaction
    end

    def find_matching_interaction(request_signature)
      @interactions.find do |interaction|
        # Handle both string and symbol keys from JSON parsing
        interaction_request = interaction['request'] || interaction[:request]
        requests_match?(interaction_request, serialize_request(request_signature))
      end
    end

    def save
      FileUtils.mkdir_p(File.dirname(@cassette_path))
      File.write(@cassette_path, JSON.pretty_generate({
        interactions: @interactions,
        recorded_with: "SSEVCR #{VERSION}"
      }))
    end

    def eject
      # Hook into the streaming client to capture real SSE data
      # This would be called when we're in recording mode
    end

    private

    def requests_match?(recorded_request, current_request)
      return false unless recorded_request && current_request
      
      # Handle string/symbol key differences
      recorded_uri = normalize_uri(recorded_request['uri'] || recorded_request[:uri])
      current_uri = normalize_uri(current_request['uri'] || current_request[:uri])
      
      recorded_method = recorded_request['method'] || recorded_request[:method]
      current_method = current_request['method'] || current_request[:method]
      
      recorded_body = recorded_request['body'] || recorded_request[:body]
      current_body = current_request['body'] || current_request[:body]
      
      method_match = recorded_method.to_s == current_method.to_s
      uri_match = recorded_uri == current_uri
      body_match = normalize_hash_keys(recorded_body) == normalize_hash_keys(current_body)
      
      
      method_match && uri_match && body_match
    end

    def normalize_uri(uri)
      # Replace any model name with a placeholder for flexible matching
      # This allows matching between gemini-1.5-flash and v1, etc.
      uri.to_s
         .gsub(/models\/[^:]+:/, 'models/MODEL:')
         .gsub(/key=[^&]+/, 'key=API_KEY')
    end
    
    def normalize_hash_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(key, value), result|
          result[key.to_s] = normalize_hash_keys(value)
        end
      when Array
        obj.map { |item| normalize_hash_keys(item) }
      else
        obj
      end
    end

    def load_existing_cassette
      return unless File.exist?(@cassette_path)
      
      data = JSON.parse(File.read(@cassette_path))
      @interactions = data['interactions'] || []
    end

    def serialize_request(request_signature)
      {
        method: request_signature[:method],
        uri: filter_sensitive_data_in_uri(request_signature[:uri]),
        body: filter_sensitive_data(request_signature[:body]),
        headers: filter_headers(request_signature[:headers])
      }
    end

    def filter_sensitive_data(data)
      return data unless data.is_a?(Hash) || data.is_a?(String)
      
      result = data.is_a?(String) ? data.dup : deep_dup_hash(data)
      
      SSEVCR.configuration.filter_sensitive_data.each do |placeholder, value|
        if result.is_a?(String)
          result.gsub!(value.to_s, placeholder)
        elsif result.is_a?(Hash)
          result = filter_hash_recursively(result, value, placeholder)
        end
      end
      
      result
    end

    def filter_sensitive_data_in_uri(uri)
      uri_string = uri.to_s
      SSEVCR.configuration.filter_sensitive_data.each do |placeholder, value|
        uri_string.gsub!(value.to_s, placeholder)
      end
      uri_string
    end

    def filter_headers(headers)
      return {} unless headers
      
      filtered = headers.dup
      # Remove authorization headers by default
      filtered.delete('Authorization')
      filtered.delete('authorization')
      filtered
    end

    def deep_dup_hash(hash)
      return hash unless hash.is_a?(Hash)
      
      hash.each_with_object({}) do |(key, value), result|
        result[key] = case value
                     when Hash
                       deep_dup_hash(value)
                     when Array
                       value.map { |item| item.is_a?(Hash) ? deep_dup_hash(item) : item }
                     else
                       value
                     end
      end
    end

    def filter_hash_recursively(hash, value, placeholder)
      hash.each do |key, val|
        if val.is_a?(String)
          hash[key] = val.gsub(value.to_s, placeholder)
        elsif val.is_a?(Hash)
          hash[key] = filter_hash_recursively(val, value, placeholder)
        elsif val.is_a?(Array)
          hash[key] = val.map do |item|
            item.is_a?(Hash) ? filter_hash_recursively(item, value, placeholder) : item
          end
        end
      end
      hash
    end
  end

  VERSION = "1.0.0"
end

# Configure SSEVCR
SSEVCR.configure do |config|
  config.cassette_library_dir = 'spec/sse_cassettes'
  config.filter_sensitive_data['<GEMINI_API_KEY>'] = ENV['GEMINI_API_KEY']
end

# Configure VCR to ignore Gemini streaming requests when SSE VCR is active
VCR.configure do |config|
  config.ignore_request do |request|
    # Ignore Gemini streaming requests when SSE VCR is handling them
    if SSEVCR.turned_on? && request.uri.include?('streamGenerateContent')
      true
    else
      false
    end
  end
end