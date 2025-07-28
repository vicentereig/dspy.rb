# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'usage'

module DSPy
  class LM
    # Base metadata struct for common fields across providers
    class ResponseMetadata < T::Struct
      extend T::Sig
      
      const :provider, String
      const :model, String
      const :response_id, T.nilable(String), default: nil
      const :created, T.nilable(Integer), default: nil
      const :structured_output, T.nilable(T::Boolean), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          provider: provider,
          model: model
        }
        hash[:response_id] = response_id if response_id
        hash[:created] = created if created
        hash[:structured_output] = structured_output unless structured_output.nil?
        hash
      end
    end
    
    # OpenAI-specific metadata with additional fields
    class OpenAIResponseMetadata < T::Struct
      extend T::Sig
      
      const :provider, String
      const :model, String
      const :response_id, T.nilable(String), default: nil
      const :created, T.nilable(Integer), default: nil
      const :structured_output, T.nilable(T::Boolean), default: nil
      const :system_fingerprint, T.nilable(String), default: nil
      const :finish_reason, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          provider: provider,
          model: model
        }
        hash[:response_id] = response_id if response_id
        hash[:created] = created if created
        hash[:structured_output] = structured_output unless structured_output.nil?
        hash[:system_fingerprint] = system_fingerprint if system_fingerprint
        hash[:finish_reason] = finish_reason if finish_reason
        hash
      end
    end
    
    # Anthropic-specific metadata with additional fields
    class AnthropicResponseMetadata < T::Struct
      extend T::Sig
      
      const :provider, String
      const :model, String
      const :response_id, T.nilable(String), default: nil
      const :created, T.nilable(Integer), default: nil
      const :structured_output, T.nilable(T::Boolean), default: nil
      const :stop_reason, T.nilable(String), default: nil
      const :stop_sequence, T.nilable(String), default: nil
      const :tool_calls, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          provider: provider,
          model: model
        }
        hash[:response_id] = response_id if response_id
        hash[:created] = created if created
        hash[:structured_output] = structured_output unless structured_output.nil?
        hash[:stop_reason] = stop_reason if stop_reason
        hash[:stop_sequence] = stop_sequence if stop_sequence
        hash[:tool_calls] = tool_calls if tool_calls
        hash
      end
    end
    
    # Normalized response format for all LM providers
    class Response < T::Struct
      extend T::Sig
      
      const :content, String
      const :usage, T.nilable(T.any(Usage, OpenAIUsage)), default: nil
      const :metadata, T.any(ResponseMetadata, OpenAIResponseMetadata, AnthropicResponseMetadata, T::Hash[Symbol, T.untyped])
      
      sig { returns(String) }
      def to_s
        content
      end
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          content: content
        }
        hash[:usage] = usage.to_h if usage
        hash[:metadata] = metadata.is_a?(Hash) ? metadata : metadata.to_h
        hash
      end
    end
    
    # Factory for creating response metadata objects
    module ResponseMetadataFactory
      extend T::Sig
      
      sig { params(provider: String, metadata: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.any(ResponseMetadata, OpenAIResponseMetadata, AnthropicResponseMetadata)) }
      def self.create(provider, metadata)
        # Handle nil metadata
        metadata ||= {}
        
        # Normalize provider name
        provider_name = provider.to_s.downcase
        
        # Extract common fields
        common_fields = {
          provider: provider,
          model: metadata[:model] || 'unknown',
          response_id: metadata[:response_id] || metadata[:id],
          created: metadata[:created],
          structured_output: metadata[:structured_output]
        }
        
        case provider_name
        when 'openai'
          OpenAIResponseMetadata.new(
            **common_fields,
            system_fingerprint: metadata[:system_fingerprint],
            finish_reason: metadata[:finish_reason]&.to_s
          )
        when 'anthropic'
          AnthropicResponseMetadata.new(
            **common_fields,
            stop_reason: metadata[:stop_reason]&.to_s,
            stop_sequence: metadata[:stop_sequence]&.to_s,
            tool_calls: metadata[:tool_calls]
          )
        else
          ResponseMetadata.new(**common_fields)
        end
      rescue => e
        DSPy.logger.debug("Failed to create response metadata: #{e.message}")
        # Fallback to basic metadata
        ResponseMetadata.new(
          provider: provider,
          model: metadata[:model] || 'unknown'
        )
      end
    end
  end
end
