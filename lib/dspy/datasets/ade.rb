# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'cgi'
require 'fileutils'

module DSPy
  module Datasets
    module ADE
      extend self

      DATASET = 'ade-benchmark-corpus/ade_corpus_v2'
      CLASSIFICATION_CONFIG = 'Ade_corpus_v2_classification'
      BASE_URL = 'https://datasets-server.huggingface.co'

      DEFAULT_CACHE_DIR = File.expand_path('../../../tmp/dspy_datasets/ade', __dir__)

      MAX_BATCH_SIZE = 100

      def examples(split: 'train', limit: 200, offset: 0, cache_dir: default_cache_dir)
        remaining = limit
        current_offset = offset
        collected = []

        while remaining.positive?
          batch_size = [remaining, MAX_BATCH_SIZE].min
          rows = fetch_rows(
            split: split,
            limit: batch_size,
            offset: current_offset,
            cache_dir: cache_dir
          )

          break if rows.empty?

          collected.concat(rows.map do |row|
            {
              'text' => row.fetch('text', ''),
              'label' => row.fetch('label', 0).to_i
            }
          end)

          current_offset += batch_size
          remaining -= batch_size
        end

        collected
      end

      def fetch_rows(split:, limit:, offset:, cache_dir:)
        FileUtils.mkdir_p(cache_dir)
        cache_path = File.join(cache_dir, "#{CLASSIFICATION_CONFIG}_#{split}_#{offset}_#{limit}.json")

        if File.exist?(cache_path)
          return JSON.parse(File.read(cache_path))
        end

        rows = request_rows(split: split, limit: limit, offset: offset)
        File.write(cache_path, JSON.pretty_generate(rows))
        rows
      end

      private

      def request_rows(split:, limit:, offset:)
        uri = URI("#{BASE_URL}/rows")
        params = {
          dataset: DATASET,
          config: CLASSIFICATION_CONFIG,
          split: split,
          offset: offset,
          length: limit
        }
        uri.query = URI.encode_www_form(params)

        response = Net::HTTP.get_response(uri)
        raise "ADE dataset request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body)
        body.fetch('rows', []).map { |row| row.fetch('row', {}) }
      end

      def default_cache_dir
        ENV['DSPY_DATASETS_CACHE'] ? File.expand_path('ade', ENV['DSPY_DATASETS_CACHE']) : DEFAULT_CACHE_DIR
      end
    end
  end
end
