# frozen_string_literal: true

require_relative 'info'

module DSPy
  module Datasets
    module Manifest
      extend self

      def all
        @all ||= [
          DatasetInfo.new(
            id: 'ade-benchmark-corpus/ade_corpus_v2',
            name: 'ADE Corpus V2',
            provider: 'huggingface',
            splits: %w[train],
            features: {
              'text' => { 'type' => 'string' },
              'label' => { 'type' => 'int64', 'description' => '0: Not-Related, 1: Related' }
            },
            loader: :huggingface_parquet,
            loader_options: {
              dataset: 'ade-benchmark-corpus/ade_corpus_v2',
              config: 'Ade_corpus_v2_classification'
            },
            metadata: {
              description: 'Adverse drug event classification corpus used in ADE optimization examples.',
              homepage: 'https://huggingface.co/datasets/ade-benchmark-corpus/ade_corpus_v2',
              approx_row_count: 23516
            }
          )
        ].freeze
      end

      def by_id(id)
        all.detect { |dataset| dataset.id == id }
      end
    end
  end
end
