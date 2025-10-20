require 'spec_helper'
require 'tempfile'
require 'dspy/datasets/ade'

RSpec.describe DSPy::Datasets::ADE do
  let(:loader) do
    instance_double(
      DSPy::Datasets::Loaders::HuggingFaceParquet,
      each_row: nil,
      row_count: 3
    )
  end

  let(:rows) do
    [
      { 'text' => 'Example A', 'label' => 1 },
      { 'text' => 'Example B', 'label' => 0 },
      { 'text' => 'Example C', 'label' => 1 }
    ]
  end

  before do
    allow(loader).to receive(:each_row) do |&block|
      rows.each(&block)
    end

    allow(DSPy::Datasets::Loaders::HuggingFaceParquet).to receive(:new).and_return(loader)
  end

  describe '.examples' do
    it 'normalizes rows from the dataset fetcher' do
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
    it 'passes through cache directory and split options' do
      Dir.mktmpdir do |dir|
        expect(DSPy::Datasets::Loaders::HuggingFaceParquet)
          .to receive(:new)
          .with(instance_of(DSPy::Datasets::DatasetInfo), split: 'train', cache_dir: dir)
          .and_return(loader)

        result = described_class.fetch_rows(split: 'train', limit: 2, offset: 0, cache_dir: dir)
        expect(result).to eq(rows.first(2))
      end
    end
  end

  describe '.examples with cache dir' do
    it 'forwards cache directory to dataset fetcher' do
      Dir.mktmpdir do |dir|
        expect(DSPy::Datasets::Loaders::HuggingFaceParquet)
          .to receive(:new)
          .with(instance_of(DSPy::Datasets::DatasetInfo), split: 'train', cache_dir: dir)
          .and_return(loader)

        described_class.examples(limit: 2, cache_dir: dir)
      end
    end
  end
end
