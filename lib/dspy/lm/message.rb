# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  class LM
    # Type-safe representation of chat messages
    class Message < T::Struct
      extend T::Sig
      
      # Role enum for type safety
      class Role < T::Enum
        enums do
          System = new('system')
          User = new('user')
          Assistant = new('assistant')
        end
      end
      
      const :role, Role
      const :content, T.any(String, T::Array[T::Hash[Symbol, T.untyped]])
      const :name, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        base = {
          role: role.serialize,
          content: content
        }
        base[:name] = name if name
        base
      end
      
      sig { returns(String) }
      def to_s
        if content.is_a?(String)
          name ? "#{role.serialize}(#{name}): #{content}" : "#{role.serialize}: #{content}"
        else
          name ? "#{role.serialize}(#{name}): [multimodal content]" : "#{role.serialize}: [multimodal content]"
        end
      end
      
      sig { returns(T::Boolean) }
      def multimodal?
        content.is_a?(Array)
      end
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_openai_format
        formatted = { role: role.serialize }
        
        if content.is_a?(String)
          formatted[:content] = content
        else
          # Convert multimodal content array to OpenAI format
          formatted[:content] = content.map do |item|
            case item[:type]
            when 'text'
              { type: 'text', text: item[:text] }
            when 'image'
              item[:image].to_openai_format
            else
              item
            end
          end
        end
        
        formatted[:name] = name if name
        formatted
      end
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_anthropic_format
        formatted = { role: role.serialize }
        
        if content.is_a?(String)
          formatted[:content] = content
        else
          # Convert multimodal content array to Anthropic format
          formatted[:content] = content.map do |item|
            case item[:type]
            when 'text'
              { type: 'text', text: item[:text] }
            when 'image'
              item[:image].to_anthropic_format
            else
              item
            end
          end
        end
        
        formatted[:name] = name if name
        formatted
      end
    end
    
    # Factory for creating Message objects from various formats
    module MessageFactory
      extend T::Sig
      
      sig { params(message_data: T.untyped).returns(T.nilable(Message)) }
      def self.create(message_data)
        return nil if message_data.nil?
        
        # Already a Message? Return as-is
        return message_data if message_data.is_a?(Message)
        
        # Convert to hash if needed
        if message_data.respond_to?(:to_h)
          message_data = message_data.to_h
        end
        
        return nil unless message_data.is_a?(Hash)
        
        # Normalize keys to symbols
        normalized = message_data.transform_keys(&:to_sym)
        
        create_from_hash(normalized)
      end
      
      sig { params(messages: T::Array[T.untyped]).returns(T::Array[Message]) }
      def self.create_many(messages)
        messages.compact.map { |m| create(m) }.compact
      end
      
      private
      
      sig { params(data: T::Hash[Symbol, T.untyped]).returns(T.nilable(Message)) }
      def self.create_from_hash(data)
        role_str = data[:role]&.to_s
        content = data[:content]
        
        return nil if role_str.nil? || content.nil?
        
        # Handle both string and array content
        formatted_content = if content.is_a?(Array)
          content
        else
          content.to_s
        end
        
        # Convert string role to enum
        role = case role_str
               when 'system' then Message::Role::System
               when 'user' then Message::Role::User
               when 'assistant' then Message::Role::Assistant
               else
                 DSPy.logger.debug("Unknown message role: #{role_str}")
                 return nil
               end
        
        Message.new(
          role: role,
          content: formatted_content,
          name: data[:name]&.to_s
        )
      rescue StandardError => e
        DSPy.logger.debug("Failed to create Message: #{e.message}")
        nil
      end
    end
  end
end