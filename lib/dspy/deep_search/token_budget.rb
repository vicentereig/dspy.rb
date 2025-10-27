# frozen_string_literal: true

module DSPy
  module DeepSearch
    class TokenBudget
      extend T::Sig

      class Exceeded < StandardError; end

      sig { returns(Integer) }
      attr_reader :limit

      sig { returns(Integer) }
      attr_reader :total_tokens

      sig { params(limit: Integer).void }
      def initialize(limit:)
        @limit = limit
        @total_tokens = T.let(0, Integer)
      end

      sig do
        params(
          prompt_tokens: Integer,
          completion_tokens: Integer
        ).void
      end
      def track!(prompt_tokens:, completion_tokens:)
        prompt = T.must(prompt_tokens)
        completion = T.must(completion_tokens)

        increment = prompt + completion
        new_total = @total_tokens + increment

        if new_total >= limit
          raise Exceeded, "Token budget exceeded: #{new_total}/#{limit}"
        end

        @total_tokens = new_total
      end
    end
  end
end
