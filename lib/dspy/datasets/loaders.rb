# frozen_string_literal: true

module DSPy
  module Datasets
    module Loaders
      extend self

      def build(info, split:, cache_dir:)
        case info.loader
        when :huggingface_parquet
          require_relative 'loaders/huggingface_parquet'
          HuggingFaceParquet.new(info, split: split, cache_dir: cache_dir)
        else
          raise DatasetError, "Unsupported loader: #{info.loader}"
        end
      end
    end
  end
end
