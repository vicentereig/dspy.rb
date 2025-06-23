# frozen_string_literal: true

module DSPy
  class LM
    # Normalized response format for all LM providers
    class Response
      attr_reader :content, :usage, :metadata

      def initialize(content:, usage: nil, metadata: {})
        @content = content
        @usage = usage
        @metadata = metadata
      end

      def to_s
        content
      end

      def to_h
        {
          content: content,
          usage: usage,
          metadata: metadata
        }
      end
    end
  end
end
