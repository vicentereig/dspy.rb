require 'spec_helper'
require 'faraday'
require 'json'

# Simple PORO to store result attributes
class ColBERTResult
  attr_reader :text, :long_text, :score, :pid, :metadata

  def initialize(attributes = {})
    @text = attributes["text"]
    @long_text = attributes["long_text"] || attributes["text"]
    @score = attributes["score"]
    @pid = attributes["pid"]
    @metadata = attributes
  end

  def [](key)
    @metadata[key]
  end

  def to_s
    "<score=#{@score} text=#{text[0,20]}...>"
  end
end

class ColBERTv2
  # Wrapper for the ColBERTv2 Retrieval API
  def initialize(url: "http://0.0.0.0")
    @url = url
    @conn = Faraday.new(url: @url) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end
  end

  def call(query, k: 10, simplify: false)
    topk = fetch_results(query, k)

    if simplify
      topk.map(&:long_text)
    else
      topk
    end
  end

  private

  def fetch_results(query, k)
    raise ArgumentError, "Only k <= 100 is supported" if k > 100

    response = @conn.get do |req|
      req.params['query'] = query
      req.params['k'] = k
    end

    data = JSON.parse(response.body)
    results = data["topk"][0...k]

    results.map { |result| ColBERTResult.new(result) }
  end
end

class ContextualQA < DSPy::Signature
  description "Answers the question taking relevant context into account"

  input do |builder|
    builder.const :context, T::Array[String], description: 'the context provided to enrich the answer'
    builder.const :question, String, description: 'the question we want to ultimately answer in the language it is written originally'
  end

  output do |builder|
    builder.const :response, String, description: 'the answer incorporating the relevant context'
  end
end

RSpec.describe 'RAG: ColBERTv2' do
  it 'retrieves stuff' do
    VCR.use_cassette('openai/gpt4o-mini/colbert_rag') do
      retriever = ColBERTv2.new(url: 'http://20.102.90.50:2017/wiki17_abstracts')
      results = retriever.call('hola')
      expect(results.length).to eq(10)
    end
  end

  it 'rags stuff' do
    VCR.use_cassette('openai/gpt4o-mini/colbert_rag_with_gen') do

      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end

      rag = DSPy::ChainOfThought.new(ContextualQA)

      retriever = ColBERTv2.new(url: 'http://20.102.90.50:2017/wiki17_abstracts')
      question = 'hola'
      context = retriever.call(question).map(&:long_text)

      prediction = rag.call(question: question, context: context)
      expect(prediction.response).to include("hola").or include("Hola").or include("magazine")
    end
  end
end
