require 'spec_helper'

RSpec.describe DSPy::Datasets do
  describe '.list' do
    it 'returns paginated dataset metadata' do
      result = described_class.list(page: 1, per_page: 1)

      expect(result.page).to eq(1)
      expect(result.per_page).to eq(1)
      expect(result.total_pages).to be >= 1
      expect(result.items.first).to be_a(DSPy::Datasets::DatasetInfo)
    end
  end

  describe '.fetch' do
    let(:info) { DSPy::Datasets::Manifest.all.first }
    let(:loader) do
      instance_double(
        DSPy::Datasets::Loaders::HuggingFaceParquet,
        each_row: nil,
        row_count: 1
      )
    end

    before do
      allow(loader).to receive(:each_row) { |&block| block.call({ 'text' => 'sample', 'label' => 1 }) }
      allow(DSPy::Datasets::Loaders).to receive(:build).and_return(loader)
    end

    it 'returns a dataset wrapper' do
      dataset = described_class.fetch(info.id, split: 'train')

      expect(dataset.info.id).to eq(info.id)
      expect(dataset.split).to eq('train')
      expect(dataset.take(1).first).to include('text', 'label')
    end

    it 'raises an error for unknown dataset' do
      expect { described_class.fetch('missing') }.to raise_error(DSPy::Datasets::DatasetNotFoundError)
    end

    it 'raises an error for invalid split' do
      expect { described_class.fetch(info.id, split: 'validation') }.to raise_error(DSPy::Datasets::InvalidSplitError)
    end
  end
end
