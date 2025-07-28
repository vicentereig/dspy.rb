# frozen_string_literal: true

require_relative 'message'

module DSPy
  class LM
    class MessageBuilder
      extend T::Sig
      
      sig { returns(T::Array[Message]) }
      attr_reader :messages

      def initialize
        @messages = []
      end

      sig { params(content: T.any(String, T.untyped)).returns(MessageBuilder) }
      def system(content)
        @messages << Message.new(
          role: Message::Role::System,
          content: content.to_s
        )
        self
      end

      sig { params(content: T.any(String, T.untyped)).returns(MessageBuilder) }
      def user(content)
        @messages << Message.new(
          role: Message::Role::User,
          content: content.to_s
        )
        self
      end

      sig { params(content: T.any(String, T.untyped)).returns(MessageBuilder) }
      def assistant(content)
        @messages << Message.new(
          role: Message::Role::Assistant,
          content: content.to_s
        )
        self
      end
      
      # For backward compatibility, allow conversion to hash array
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def to_h
        @messages.map(&:to_h)
      end
    end
  end
end