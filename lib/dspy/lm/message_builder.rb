# frozen_string_literal: true

module DSPy
  class LM
    class MessageBuilder
      attr_reader :messages

      def initialize
        @messages = []
      end

      def system(content)
        @messages << { role: 'system', content: content.to_s }
        self
      end

      def user(content)
        @messages << { role: 'user', content: content.to_s }
        self
      end

      def assistant(content)
        @messages << { role: 'assistant', content: content.to_s }
        self
      end
    end
  end
end