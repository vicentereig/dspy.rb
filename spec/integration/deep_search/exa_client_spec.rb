# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_search"

RSpec.describe DSPy::DeepSearch::Clients::ExaClient do
  subject(:client) { described_class.new }

  let(:query) { "Jina DeepSearch architecture" }

  describe "#search" do
    it "returns normalized results", :vcr do
      results = client.search(query: query, num_results: 2)

      expect(results).not_to be_empty
      expect(results.first.url).to match(%r{^https?://})
      expect(results.first.highlights).to be_a(Array)
    end
  end

  describe "#contents" do
    it "fetches enriched content for URLs", :vcr do
      urls = client.search(query: query, num_results: 1).map(&:url)

      contents = client.contents(urls: urls)

      expect(contents.length).to eq(1)
      expect(contents.first.url).to eq(urls.first)
      expect(contents.first.text).to be_a(String)
      expect(contents.first.text).not_to be_empty
    end
  end
end
