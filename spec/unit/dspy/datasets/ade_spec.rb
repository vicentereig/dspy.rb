require 'spec_helper'
require 'tempfile'
require 'dspy/datasets/ade'

RSpec.describe DSPy::Datasets::ADE do
  describe '.examples' do
    it 'fetches structured rows from the dataset server', vcr: { cassette_name: 'datasets/ade_rows' } do
      rows = described_class.examples(limit: 5)
      expect(rows).to be_an(Array)
      expect(rows).not_to be_empty

      first = rows.first
      expect(first).to include('text', 'label')
      expect(first['text']).to be_a(String)
      expect([0, 1]).to include(first['label'])
    end
  end

  describe '.fetch_rows' do
    it 'caches responses to the provided directory', :aggregate_failures, vcr: { cassette_name: 'datasets/ade_rows_small' } do
      Dir.mktmpdir do |dir|
        result_a = described_class.fetch_rows(split: 'train', limit: 3, offset: 0, cache_dir: dir)
        expect(result_a).to be_an(Array)
        expect(Dir.children(dir).size).to eq(1)

        result_b = described_class.fetch_rows(split: 'train', limit: 3, offset: 0, cache_dir: dir)
        expect(result_b).to eq(result_a)
      end
    end
  end

  describe '.examples with cache dir' do
    it 'writes cache files into the directory when provided', vcr: { cassette_name: 'datasets/ade_rows_two' } do
      Dir.mktmpdir do |dir|
        described_class.examples(limit: 2, cache_dir: dir)
        cache_files = Dir.glob(File.join(dir, '*.json'))
        expect(cache_files).not_to be_empty
      end
    end
  end
end
