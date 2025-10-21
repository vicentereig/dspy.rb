require 'spec_helper'
require 'dspy/datasets/hugging_face/api'

RSpec.describe DSPy::Datasets::HuggingFace::Client, :datasets do
  subject(:client) { described_class.new }

  let(:base_url) { DSPy::Datasets::HuggingFace::Client::BASE_URL }

  before do
    WebMock.enable!
  end

  after do
    WebMock.reset!
  end

  describe '#list_datasets' do
    it 'requests the public datasets index with provided filters' do
      stub_request(:get, "#{base_url}/api/datasets")
        .with(query: hash_including('search' => 'ade', 'limit' => '5', 'filter' => 'task_categories:text-classification'))
        .to_return(
          status: 200,
          body: [
            {
              'id' => 'ade-benchmark-corpus/ade_corpus_v2',
              'author' => 'ade-benchmark-corpus',
              'disabled' => false,
              'gated' => false,
              'private' => false,
              'likes' => 10,
              'downloads' => 1000,
              'tags' => ['task_categories:text-classification'],
              'sha' => 'abc123',
              'lastModified' => '2024-01-09T11:42:58.000Z',
              'description' => 'ADE dataset'
            }
          ].to_json
        )

      params = DSPy::Datasets::HuggingFace::ListParams.new(
        search: 'ade',
        limit: 5,
        filter: ['task_categories:text-classification']
      )
      summaries = client.list_datasets(params)

      expect(summaries.size).to eq(1)
      summary = summaries.first
      expect(summary.id).to eq('ade-benchmark-corpus/ade_corpus_v2')
      expect(summary.tags).to include('task_categories:text-classification')
      expect(summary.last_modified).to be_a(Time)
    end
  end

  describe '#dataset' do
    it 'retrieves detailed metadata for a dataset' do
      stub_request(:get, "#{base_url}/api/datasets/ade-benchmark-corpus/ade_corpus_v2")
        .to_return(
          status: 200,
          body: {
            'id' => 'ade-benchmark-corpus/ade_corpus_v2',
            'author' => 'ade-benchmark-corpus',
            'disabled' => false,
            'gated' => false,
            'private' => false,
            'likes' => 33,
            'downloads' => 1036,
            'tags' => ['task_categories:text-classification'],
            'sha' => '4ba01c71687dd7c996597042449448ea312126cf',
            'siblings' => [
              { 'rfilename' => 'README.md', 'size' => 12345 }
            ],
            'configs' => [
              { 'config_name' => 'Ade_corpus_v2_classification' }
            ],
            'cardData' => { 'pretty_name' => 'Adverse Drug Reaction Data v2' }
          }.to_json
        )

      details = client.dataset('ade-benchmark-corpus/ade_corpus_v2')
      expect(details.summary.id).to eq('ade-benchmark-corpus/ade_corpus_v2')
      expect(details.siblings.first.rfilename).to eq('README.md')
      expect(details.card_data).to include('pretty_name' => 'Adverse Drug Reaction Data v2')
    end
  end

  describe '#dataset_parquet' do
    it 'returns parquet download urls mapped by config and split' do
      stub_request(:get, "#{base_url}/api/datasets/foo/bar/parquet")
        .to_return(
          status: 200,
          body: {
            'config_a' => {
              'train' => ['https://example.com/a/train/0.parquet'],
              'test' => ['https://example.com/a/test/0.parquet']
            }
          }.to_json
        )

      listing = client.dataset_parquet('foo/bar')
      expect(listing.files['config_a']['train']).to eq(['https://example.com/a/train/0.parquet'])
    end
  end

  describe '#dataset_tags_by_type' do
    it 'parses available dataset tags grouped by type' do
      stub_request(:get, "#{base_url}/api/datasets-tags-by-type")
        .to_return(
          status: 200,
          body: {
            'license' => [
              { 'id' => 'license:mit', 'label' => 'mit', 'type' => 'license' }
            ]
          }.to_json
        )

      tags = client.dataset_tags_by_type
      expect(tags.tags['license'].first.id).to eq('license:mit')
    end
  end

  describe 'error handling' do
    it 'raises APIError on non-success responses' do
      stub_request(:get, "#{base_url}/api/datasets")
        .to_return(status: 500, body: 'oops')

      expect do
        client.list_datasets
      end.to raise_error(DSPy::Datasets::HuggingFace::APIError)
    end
  end
end
