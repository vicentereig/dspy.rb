# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class LM
    # Manages caching for schemas and capability detection
    class CacheManager
      extend T::Sig
      
      # Cache entry with TTL
      class CacheEntry < T::Struct
        extend T::Sig
        
        const :value, T.untyped
        const :expires_at, Time
        
        sig { returns(T::Boolean) }
        def expired?
          Time.now > expires_at
        end
      end
      
      DEFAULT_TTL = 3600 # 1 hour
      
      sig { void }
      def initialize
        @schema_cache = {}
        @capability_cache = {}
        @mutex = Mutex.new
      end
      
      # Cache a schema for a signature class
      sig { params(signature_class: T.class_of(DSPy::Signature), provider: String, schema: T.untyped, cache_params: T::Hash[Symbol, T.untyped]).void }
      def cache_schema(signature_class, provider, schema, cache_params = {})
        key = schema_key(signature_class, provider, cache_params)
        
        @mutex.synchronize do
          @schema_cache[key] = CacheEntry.new(
            value: schema,
            expires_at: Time.now + DEFAULT_TTL
          )
        end
        
        DSPy.logger.debug("Cached schema for #{signature_class.name} (#{provider})")
      end
      
      # Get cached schema if available
      sig { params(signature_class: T.class_of(DSPy::Signature), provider: String, cache_params: T::Hash[Symbol, T.untyped]).returns(T.nilable(T.untyped)) }
      def get_schema(signature_class, provider, cache_params = {})
        key = schema_key(signature_class, provider, cache_params)
        
        @mutex.synchronize do
          entry = @schema_cache[key]
          
          if entry.nil?
            nil
          elsif entry.expired?
            @schema_cache.delete(key)
            nil
          else
            entry.value
          end
        end
      end
      
      # Cache capability detection result
      sig { params(model: String, capability: String, result: T::Boolean).void }
      def cache_capability(model, capability, result)
        key = capability_key(model, capability)
        
        @mutex.synchronize do
          @capability_cache[key] = CacheEntry.new(
            value: result,
            expires_at: Time.now + DEFAULT_TTL * 24 # Capabilities change less frequently
          )
        end
        
        DSPy.logger.debug("Cached capability #{capability} for #{model}: #{result}")
      end
      
      # Get cached capability if available
      sig { params(model: String, capability: String).returns(T.nilable(T::Boolean)) }
      def get_capability(model, capability)
        key = capability_key(model, capability)
        
        @mutex.synchronize do
          entry = @capability_cache[key]
          
          if entry.nil?
            nil
          elsif entry.expired?
            @capability_cache.delete(key)
            nil
          else
            entry.value
          end
        end
      end
      
      # Clear all caches
      sig { void }
      def clear!
        @mutex.synchronize do
          @schema_cache.clear
          @capability_cache.clear
        end
        
        DSPy.logger.debug("Cleared all caches")
      end
      
      # Get cache statistics
      sig { returns(T::Hash[Symbol, Integer]) }
      def stats
        @mutex.synchronize do
          {
            schema_entries: @schema_cache.size,
            capability_entries: @capability_cache.size,
            total_entries: @schema_cache.size + @capability_cache.size
          }
        end
      end
      
      private
      
      sig { params(signature_class: T.class_of(DSPy::Signature), provider: String, cache_params: T::Hash[Symbol, T.untyped]).returns(String) }
      def schema_key(signature_class, provider, cache_params = {})
        params_str = cache_params.sort.map { |k, v| "#{k}:#{v}" }.join(":")
        base_key = "schema:#{provider}:#{signature_class.name}"
        params_str.empty? ? base_key : "#{base_key}:#{params_str}"
      end
      
      sig { params(model: String, capability: String).returns(String) }
      def capability_key(model, capability)
        "capability:#{model}:#{capability}"
      end
    end
    
    # Global cache instance
    @cache_manager = T.let(nil, T.nilable(CacheManager))
    
    class << self
      extend T::Sig
      
      sig { returns(CacheManager) }
      def cache_manager
        @cache_manager ||= CacheManager.new
      end
    end
  end
end