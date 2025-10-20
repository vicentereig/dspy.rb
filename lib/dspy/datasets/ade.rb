# frozen_string_literal: true

module DSPy
  module Datasets
    module ADE
      extend self

      DATASET_ID = 'ade-benchmark-corpus/ade_corpus_v2'

      def examples(split: 'train', limit: 200, offset: 0, cache_dir: nil)
        dataset = DSPy::Datasets.fetch(DATASET_ID, split: split, cache_dir: cache_dir)
        dataset.rows(limit: limit, offset: offset).map do |row|
          {
            'text' => row.fetch('text', '').to_s,
            'label' => row.fetch('label', 0).to_i
          }
        end
      end

      def fetch_rows(split:, limit:, offset:, cache_dir: nil)
        dataset = DSPy::Datasets.fetch(DATASET_ID, split: split, cache_dir: cache_dir)
        dataset.rows(limit: limit, offset: offset)
      end
    end
  end
end
