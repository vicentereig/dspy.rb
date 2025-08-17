# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  class LM
    # Base class for token usage information
    class Usage < T::Struct
      extend T::Sig
      
      const :input_tokens, Integer
      const :output_tokens, Integer
      const :total_tokens, Integer
      
      sig { returns(Hash) }
      def to_h
        {
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens
        }
      end
    end
    
    # OpenAI-specific usage information with additional fields
    class OpenAIUsage < T::Struct
      extend T::Sig
      
      const :input_tokens, Integer
      const :output_tokens, Integer
      const :total_tokens, Integer
      const :prompt_tokens_details, T.nilable(T::Hash[Symbol, Integer]), default: nil
      const :completion_tokens_details, T.nilable(T::Hash[Symbol, Integer]), default: nil
      
      sig { returns(Hash) }
      def to_h
        base = {
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens
        }
        base[:prompt_tokens_details] = prompt_tokens_details if prompt_tokens_details
        base[:completion_tokens_details] = completion_tokens_details if completion_tokens_details
        base
      end
    end
    
    # Factory for creating appropriate usage objects
    module UsageFactory
      extend T::Sig
      
      sig { params(provider: String, usage_data: T.untyped).returns(T.nilable(T.any(Usage, OpenAIUsage))) }
      def self.create(provider, usage_data)
        return nil if usage_data.nil?
        
        # If already a Usage struct, return as-is
        return usage_data if usage_data.is_a?(Usage)
        
        # Handle test doubles by converting to hash
        if usage_data.respond_to?(:to_h)
          usage_data = usage_data.to_h
        end
        
        # Convert hash to appropriate struct
        return nil unless usage_data.is_a?(Hash)
        
        # Normalize keys to symbols
        normalized = usage_data.transform_keys(&:to_sym)
        
        case provider.to_s.downcase
        when 'openai'
          create_openai_usage(normalized)
        when 'anthropic'
          create_anthropic_usage(normalized)
        when 'gemini'
          create_gemini_usage(normalized)
        else
          create_generic_usage(normalized)
        end
      end
      
      private
      
      sig { params(data: T::Hash[Symbol, T.untyped]).returns(T.nilable(OpenAIUsage)) }
      def self.create_openai_usage(data)
        # OpenAI uses prompt_tokens/completion_tokens
        input_tokens = data[:prompt_tokens] || data[:input_tokens] || 0
        output_tokens = data[:completion_tokens] || data[:output_tokens] || 0
        total_tokens = data[:total_tokens] || (input_tokens + output_tokens)
        
        # Convert prompt_tokens_details and completion_tokens_details to hashes if needed
        prompt_details = convert_to_hash(data[:prompt_tokens_details])
        completion_details = convert_to_hash(data[:completion_tokens_details])
        
        OpenAIUsage.new(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens,
          prompt_tokens_details: prompt_details,
          completion_tokens_details: completion_details
        )
      rescue => e
        DSPy.logger.debug("Failed to create OpenAI usage: #{e.message}")
        nil
      end
      
      sig { params(value: T.untyped).returns(T.nilable(T::Hash[Symbol, Integer])) }
      def self.convert_to_hash(value)
        return nil if value.nil?
        return value if value.is_a?(Hash) && value.keys.all? { |k| k.is_a?(Symbol) }
        
        # Convert object to hash if it responds to to_h
        if value.respond_to?(:to_h)
          hash = value.to_h
          # Ensure symbol keys and integer values
          hash.transform_keys(&:to_sym).transform_values(&:to_i)
        else
          nil
        end
      rescue
        nil
      end
      
      sig { params(data: T::Hash[Symbol, T.untyped]).returns(T.nilable(Usage)) }
      def self.create_anthropic_usage(data)
        # Anthropic uses input_tokens/output_tokens
        input_tokens = data[:input_tokens] || 0
        output_tokens = data[:output_tokens] || 0
        total_tokens = data[:total_tokens] || (input_tokens + output_tokens)
        
        Usage.new(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens
        )
      rescue => e
        DSPy.logger.debug("Failed to create Anthropic usage: #{e.message}")
        nil
      end
      
      sig { params(data: T::Hash[Symbol, T.untyped]).returns(T.nilable(Usage)) }
      def self.create_gemini_usage(data)
        # Gemini uses promptTokenCount/candidatesTokenCount/totalTokenCount
        input_tokens = data[:promptTokenCount] || data[:input_tokens] || 0
        output_tokens = data[:candidatesTokenCount] || data[:output_tokens] || 0
        total_tokens = data[:totalTokenCount] || data[:total_tokens] || (input_tokens + output_tokens)
        
        Usage.new(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens
        )
      rescue => e
        DSPy.logger.debug("Failed to create Gemini usage: #{e.message}")
        nil
      end
      
      sig { params(data: T::Hash[Symbol, T.untyped]).returns(T.nilable(Usage)) }
      def self.create_generic_usage(data)
        # Generic fallback
        input_tokens = data[:input_tokens] || data[:prompt_tokens] || 0
        output_tokens = data[:output_tokens] || data[:completion_tokens] || 0
        total_tokens = data[:total_tokens] || (input_tokens + output_tokens)
        
        Usage.new(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens
        )
      rescue => e
        DSPy.logger.debug("Failed to create generic usage: #{e.message}")
        nil
      end
    end
  end
end