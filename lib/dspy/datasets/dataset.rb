# frozen_string_literal: true

module DSPy
  module Datasets
    class Dataset
      include Enumerable

      attr_reader :info, :split

      def initialize(info:, split:, loader:)
        @info = info
        @split = split
        @loader = loader
      end

      def each
        return enum_for(:each) unless block_given?

        @loader.each_row do |row|
          yield row
        end
      end

      def rows(limit: nil, offset: 0)
        enumerator = each
        enumerator = enumerator.drop(offset) if offset.positive?
        limit ? enumerator.take(limit) : enumerator.to_a
      end

      def size
        @loader.row_count
      end

      alias count size

      def features
        info.features
      end

      def metadata
        info.metadata
      end
    end
  end
end
