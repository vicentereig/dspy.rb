# frozen_string_literal: true

require "set"

module DSPy
  module DeepSearch
    class GapQueue
      extend T::Sig

      class Empty < StandardError; end

      sig { void }
      def initialize
        @queue = T.let([], T::Array[T.untyped])
        @seen = T.let(Set.new, T::Set[T.untyped])
      end

      sig { params(item: T.untyped).void }
      def enqueue(item)
        return if @seen.include?(item)

        @queue << item
        @seen << item
      end

      sig { returns(T.untyped) }
      def dequeue
        raise Empty, "No items remaining in gap queue" if @queue.empty?

        item = @queue.shift
        @seen.delete(item)
        item
      end

      sig { returns(Integer) }
      def size
        @queue.length
      end

      sig { returns(T::Boolean) }
      def empty?
        @queue.empty?
      end
    end
  end
end
