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
          ),
          DatasetInfo.new(
            id: 'hotpot_qa/fullwiki',
            name: 'HotPotQA (FullWiki)',
            provider: 'huggingface',
            splits: %w[train validation],
            features: {
              'id' => { 'type' => 'string' },
              'question' => { 'type' => 'string' },
              'answer' => { 'type' => 'string' },
              'level' => { 'type' => 'string' }
            },
            loader: :huggingface_parquet,
            loader_options: {
              dataset: 'hotpot_qa',
              config: 'fullwiki'
            },
            metadata: {
              description: 'HotPotQA FullWiki configuration. The DSPy::Datasets::HotPotQA helper further filters to hard examples and produces train/dev/test splits.',
              homepage: 'https://huggingface.co/datasets/hotpot_qa',
              approx_row_count: 112_000
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
