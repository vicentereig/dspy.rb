# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class LM
    # Simple chat strategy that passes messages through without JSON extraction
    class ChatStrategy
      extend T::Sig

      sig { params(adapter: T.untyped).void }
      def initialize(adapter)
        @adapter = adapter
      end

      # No modifications to messages for simple chat
      sig { params(messages: T::Array[T::Hash[Symbol, T.untyped]], request_params: T::Hash[Symbol, T.untyped]).void }
      def prepare_request(messages, request_params)
        # Pass through unchanged
      end

      # No JSON extraction for chat
      sig { params(response: DSPy::LM::Response).returns(NilClass) }
      def extract_json(response)
        nil
      end

      sig { returns(String) }
      def name
        'chat'
      end

      private

      attr_reader :adapter
    end
  end
end
