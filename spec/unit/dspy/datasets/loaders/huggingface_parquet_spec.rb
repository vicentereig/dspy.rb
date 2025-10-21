require 'spec_helper'

loader_available = begin
  require 'dspy/datasets'
  require 'dspy/datasets/loaders/huggingface_parquet'
  true
rescue LoadError
  false
end

if loader_available
  RSpec.describe DSPy::Datasets::Loaders::HuggingFaceParquet, :datasets do
    let(:info) { DSPy::Datasets::Manifest.all.first }
    let(:parquet_url) { 'https://example.org/ade/train/0000.parquet' }
    let(:temp_parquet) do
      file = Tempfile.new(['ade_sample', '.parquet'])
      table = Arrow::Table.new(
        'text' => Arrow::StringArray.new(['Sample row 1', 'Sample row 2']),
        'label' => Arrow::Int64Array.new([1, 0])
      )
      table.save(file.path)
      file
    end

    before do
      stub_request(:get, 'https://datasets-server.huggingface.co/parquet')
        .with(query: hash_including('dataset' => info.loader_options[:dataset], 'config' => info.loader_options[:config], 'split' => 'train'))
        .to_return(status: 200, body: {
          parquet_files: [
            {
              'url' => parquet_url,
              'filename' => '0000.parquet'
            }
          ]
        }.to_json, headers: { 'Content-Type' => 'application/json' })

      stub_request(:get, parquet_url)
        .to_return(status: 200, body: File.binread(temp_parquet.path), headers: { 'Content-Type' => 'application/octet-stream' })
    end

    after do
      temp_parquet.close!
    end

    it 'downloads, caches, and iterates rows' do
      Dir.mktmpdir do |dir|
        loader = described_class.new(info, split: 'train', cache_dir: dir)

        rows = loader.each_row.to_a
        expect(rows.size).to eq(2)
        expect(rows.first).to eq('text' => 'Sample row 1', 'label' => 1)

        expect(loader.row_count).to eq(2)

        cached_files = Dir.glob(File.join(dir, '**', '*.parquet'))
        expect(cached_files.size).to eq(1)
      end
    end
  end
else
  RSpec.describe 'DSPy::Datasets::Loaders::HuggingFaceParquet', :datasets do
    it 'skips when parquet extension is unavailable' do
      skip 'parquet extension unavailable; skipping dataset loader specs'
    end
  end
end
