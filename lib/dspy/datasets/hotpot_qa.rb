# frozen_string_literal: true

require 'set'
require_relative 'info'
require_relative 'loaders'

module DSPy
  module Datasets
    # Ruby implementation of the HotPotQA dataset loader backed by Hugging Face parquet files.
    # Provides convenience helpers to create train/dev/test splits matching the Python DSPy defaults.
    class HotPotQA
      DATASET_INFO = DatasetInfo.new(
        id: 'hotpotqa/hotpot_qa/fullwiki',
        name: 'HotPotQA (FullWiki)',
        provider: 'huggingface',
        splits: %w[train validation],
        features: {
          'id' => { 'type' => 'string' },
          'question' => { 'type' => 'string' },
          'answer' => { 'type' => 'string' },
          'level' => { 'type' => 'string' },
          'type' => { 'type' => 'string' },
          'supporting_facts' => { 'type' => 'list' },
          'context' => { 'type' => 'list' }
        },
        loader: :huggingface_parquet,
        loader_options: {
          dataset: ['hotpotqa/hotpot_qa', 'hotpot_qa'],
          config: 'fullwiki'
        },
        metadata: {
          description: 'HotPotQA FullWiki split filtered to hard examples. Train split is further divided into train/dev (75/25) matching Python DSPy defaults. Supports dataset rename on Hugging Face.',
          homepage: 'https://huggingface.co/datasets/hotpot_qa',
          approx_row_count: 112_000
        }
      ).freeze

      DEFAULT_KEEP_DETAILS = :dev_titles

      attr_reader :train_size, :dev_size, :test_size

      def initialize(
        only_hard_examples: true,
        keep_details: DEFAULT_KEEP_DETAILS,
        unofficial_dev: true,
        train_seed: 0,
        train_size: nil,
        dev_size: nil,
        test_size: nil,
        cache_dir: nil
      )
        raise ArgumentError, 'only_hard_examples must be true' unless only_hard_examples

        @keep_details = keep_details
        @unofficial_dev = unofficial_dev
        @train_seed = train_seed
        @train_size = train_size
        @dev_size = dev_size
        @test_size = test_size
        @cache_dir = cache_dir
        @loaded = false
      end

      def train
        ensure_loaded
        subset(@train_examples, train_size)
      end

      def dev
        ensure_loaded
        subset(@dev_examples, dev_size)
      end

      def test
        ensure_loaded
        subset(@test_examples, test_size)
      end

      def context_lookup
        ensure_loaded
        @context_lookup ||= begin
          all_examples = @train_examples + @dev_examples + @test_examples
          all_examples.each_with_object({}) do |example, memo|
            memo[example[:question]] = example[:context] || []
          end
        end
      end

      private

      attr_reader :keep_details, :unofficial_dev, :train_seed, :cache_dir

      def ensure_loaded
        return if @loaded

        load_data
        @loaded = true
      end

      def subset(examples, limit)
        return examples unless limit

        examples.first(limit)
      end

      def load_data
        train_rows = collect_rows(split: 'train')
        shuffled = train_rows.shuffle(random: Random.new(train_seed))
        split_point = (shuffled.length * 0.75).floor

        @train_examples = shuffled.first(split_point)
        @dev_examples = unofficial_dev ? shuffled.drop(split_point) : []

        if keep_details == DEFAULT_KEEP_DETAILS
          @train_examples.each { |example| example.delete(:gold_titles) }
        end

        @test_examples = collect_rows(split: 'validation')
      end

      def collect_rows(split:)
        loader = Loaders.build(DATASET_INFO, split: split, cache_dir: cache_dir)
        examples = []

        loader.each_row do |row|
          next unless row['level'] == 'hard'

          examples << transform_row(row)
        end

        examples
      end

      def transform_row(row)
        example = {
          id: row['id'],
          question: row['question'],
          answer: row['answer'],
          type: row['type'],
          context: normalize_context(row['context']),
          gold_titles: extract_gold_titles(row['supporting_facts'])
        }

        example.delete(:context) unless example[:context]&.any?
        example.delete(:gold_titles) if example[:gold_titles].empty?
        example
      end

      def normalize_context(raw_context)
        return [] unless raw_context.respond_to?(:map)

        raw_context.map do |pair|
          if pair.is_a?(Array) && pair.size == 2
            title, sentences = pair
            sentences_text = if sentences.is_a?(Array)
                               sentences.join(' ')
                             else
                               sentences.to_s
                             end
            "#{title}: #{sentences_text}".strip
          else
            pair.to_s
          end
        end
      end

      def extract_gold_titles(supporting_facts)
        case supporting_facts
        when Hash
          titles = supporting_facts['title'] || supporting_facts[:title]
          Array(titles).to_set
        when Array
          supporting_facts.each_with_object(Set.new) do |fact, memo|
            memo << (fact.is_a?(Array) ? fact[0] : fact)
          end
        else
          Set.new
        end
      end
    end
  end
end
