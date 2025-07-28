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
      const :content, String
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
        name ? "#{role.serialize}(#{name}): #{content}" : "#{role.serialize}: #{content}"
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
        content = data[:content]&.to_s
        
        return nil if role_str.nil? || content.nil?
        
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
          content: content,
          name: data[:name]&.to_s
        )
      rescue => e
        DSPy.logger.debug("Failed to create Message: #{e.message}")
        nil
      end
    end
  end
end