# frozen_string_literal: true

module DSPy
  module Datasets
    class DatasetInfo
      attr_reader :id, :name, :provider, :splits, :features, :loader, :loader_options, :metadata

      def initialize(id:, name:, provider:, splits:, features:, loader:, loader_options:, metadata: {})
        @id = id
        @name = name
        @provider = provider
        @splits = Array(splits).map(&:to_s).freeze
        @features = features.freeze
        @loader = loader
        @loader_options = loader_options.freeze
        @metadata = metadata.freeze
      end

      def default_split
        @splits.first
      end
    end
  end
end
