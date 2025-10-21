# frozen_string_literal: true

require_relative 'datasets/version'
require_relative 'datasets/errors'
require_relative 'datasets/dataset'
require_relative 'datasets/manifest'
require_relative 'datasets/loaders'
require_relative 'datasets/hugging_face/api'
require_relative 'datasets/ade'
require_relative 'datasets/hotpot_qa'

module DSPy
  module Datasets
    PaginatedList = Struct.new(:items, :page, :per_page, :total_count, keyword_init: true) do
      def total_pages
        return 0 if per_page.zero?

        (total_count.to_f / per_page).ceil
      end
    end

    module_function

    def list(page: 1, per_page: 20)
      page = [page.to_i, 1].max
      per_page = [per_page.to_i, 1].max

      all = Manifest.all
      offset = (page - 1) * per_page
      slice = offset >= all.length ? [] : all.slice(offset, per_page) || []

      PaginatedList.new(
        items: slice,
        page: page,
        per_page: per_page,
        total_count: all.length
      )
    end

    def fetch(dataset_id, split: nil, cache_dir: nil)
      info = Manifest.by_id(dataset_id)
      raise DatasetNotFoundError, "Unknown dataset: #{dataset_id}" unless info

      split ||= info.default_split
      split = split.to_s
      unless info.splits.include?(split)
        raise InvalidSplitError, "Invalid split '#{split}' for dataset #{dataset_id} (available: #{info.splits.join(', ')})"
      end

      loader = Loaders.build(info, split: split, cache_dir: cache_dir)
      Dataset.new(info: info, split: split, loader: loader)
    end
  end
end
