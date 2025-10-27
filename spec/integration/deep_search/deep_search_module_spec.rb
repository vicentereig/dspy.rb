# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_search"
require "ostruct"

RSpec.describe DSPy::DeepSearch::Module do
  let(:search_client) { DSPy::DeepSearch::Clients::ExaClient.new }

  let(:seed_predictor) do
    Class.new do
      def call(question:)
        OpenStruct.new(query: question)
      end
    end.new
  end

  let(:reader_predictor) do
    Class.new do
      def call(url:)
        OpenStruct.new(notes: [])
      end
    end.new
  end

  let(:reason_predictor) do
    Class.new do
      def call(question:, insights:)
        if insights.size >= 4
          OpenStruct.new(
            decision: DSPy::DeepSearch::Signatures::ReasonStep::Decision::Answer,
            refined_query: nil,
            draft_answer: "Answer for #{question}: #{insights.first(3).join(' ')}"
          )
        else
          OpenStruct.new(
            decision: DSPy::DeepSearch::Signatures::ReasonStep::Decision::ContinueSearch,
            refined_query: "#{question} DeepSearch",
            draft_answer: nil
          )
        end
      end
    end.new
  end

  let(:module_instance) do
    described_class.new(
      token_budget: DSPy::DeepSearch::TokenBudget.new(limit: 10_000),
      seed_predictor: seed_predictor,
      reader_predictor: reader_predictor,
      reason_predictor: reason_predictor,
      search_client: search_client
    )
  end

  it "produces an answer with citations from Exa", :vcr do
    result = module_instance.call(question: "What is Jina DeepSearch?")

    expect(result.answer).to include("DeepSearch")
    expect(result.notes).not_to be_empty
    expect(result.citations).not_to be_empty
  end
end
