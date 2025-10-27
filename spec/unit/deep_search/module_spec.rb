# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_search"
require "ostruct"

RSpec.describe DSPy::DeepSearch::Module do
  class InstrumentedPredictor < DSPy::Module
    attr_reader :instruction_calls, :example_calls

    def initialize(handler)
      super()
      @handler = handler
      @instruction_calls = []
      @example_calls = []
    end

    def forward_untyped(**kwargs)
      @handler.call(**kwargs)
    end

    def with_instruction(instruction)
      clone = self.class.new(@handler)
      clone.instance_variable_set(:@instruction_calls, @instruction_calls + [instruction])
      clone.instance_variable_set(:@example_calls, @example_calls.dup)
      clone
    end

    def with_examples(examples)
      clone = self.class.new(@handler)
      clone.instance_variable_set(:@instruction_calls, @instruction_calls.dup)
      clone.instance_variable_set(:@example_calls, @example_calls + [examples])
      clone
    end
  end

  let(:seed_predictor) do
    InstrumentedPredictor.new(->(question:) { OpenStruct.new(query: "initial #{question}") })
  end

  let(:reader_predictor) do
    InstrumentedPredictor.new(->(url:) { OpenStruct.new(notes: ["note from #{url}"]) })
  end

  let(:decision_queue) do
    [
      OpenStruct.new(
        decision: DSPy::DeepSearch::Signatures::ReasonStep::Decision::ContinueSearch,
        refined_query: "refined query",
        draft_answer: nil
      ),
      OpenStruct.new(
        decision: DSPy::DeepSearch::Signatures::ReasonStep::Decision::Answer,
        refined_query: nil,
        draft_answer: "final answer"
      )
    ]
  end

  let(:reason_predictor) do
    queue = decision_queue.dup
    InstrumentedPredictor.new(->(question:, insights:) { queue.shift || queue.last })
  end

  let(:search_results_queue) do
    [
      [OpenStruct.new(url: "https://example.com/1")],
      [OpenStruct.new(url: "https://example.com/2")],
      []
    ]
  end

  let(:client) do
    queue = search_results_queue
    contents = {
      "https://example.com/1" => DSPy::DeepSearch::Clients::ExaClient::Content.new(
        url: "https://example.com/1",
        text: "Body 1",
        summary: "Summary for https://example.com/1",
        highlights: ["Highlight from https://example.com/1"]
      ),
      "https://example.com/2" => DSPy::DeepSearch::Clients::ExaClient::Content.new(
        url: "https://example.com/2",
        text: "Body 2",
        summary: "Summary for https://example.com/2",
        highlights: ["Highlight from https://example.com/2"]
      )
    }

    Class.new(DSPy::DeepSearch::Clients::ExaClient) do
      attr_reader :search_calls

      define_method(:initialize) do
        @queue = queue.map(&:dup)
        @contents = contents
        @search_calls = []
      end

      define_method(:search) do |query:, num_results:, autoprompt:|
        @search_calls << { query: query, num_results: num_results, autoprompt: autoprompt }
        @queue.shift || []
      end

      define_method(:contents) do |urls:, **_opts|
        Array(urls).map { |url| @contents.fetch(url) }
      end
    end.new
  end

  let(:token_budget) { DSPy::DeepSearch::TokenBudget.new(limit: 10_000) }

  let(:module_instance) do
    described_class.new(
      token_budget: token_budget,
      seed_predictor: seed_predictor,
      search_predictor: nil,
      reader_predictor: reader_predictor,
      reason_predictor: reason_predictor,
      search_client: client
    )
  end

  it "loops until the reasoner returns an answer" do
    result = module_instance.call(question: "DeepSearch intent")

    expect(result.answer).to eq("final answer")
    expect(result.notes).to include("note from https://example.com/1")
    expect(client.search_calls.map { |call| call[:query] }).to include("initial DeepSearch intent", "refined query")
  end

  it "raises when token budget is exceeded" do
    allow(token_budget).to receive(:track!).and_raise(DSPy::DeepSearch::TokenBudget::Exceeded)

    expect { module_instance.call(question: "DeepSearch intent") }
      .to raise_error(DSPy::DeepSearch::Module::TokenBudgetExceeded)
  end

  it "exposes predictors for optimizers" do
    names = module_instance.named_predictors.map(&:first)
    expect(names).to contain_exactly("seed_predictor", "reader_predictor", "reason_predictor")
  end

  it "propagates instructions to nested predictors" do
    updated = module_instance.with_instruction("Refine")
    expect(updated).not_to equal(module_instance)

    updated_map = updated.named_predictors.to_h
    expect(updated_map["seed_predictor"].instruction_calls).to include("Refine")
    expect(updated_map["reader_predictor"].instruction_calls).to include("Refine")
    expect(updated_map["reason_predictor"].instruction_calls).to include("Refine")

    original_map = module_instance.named_predictors.to_h
    expect(original_map["seed_predictor"].instruction_calls).to be_empty
  end

  it "propagates examples to nested predictors" do
    examples = [DSPy::FewShotExample.new(input: { problem: "1+1" }, output: { answer: 2 }, reasoning: "1+1=2")]
    updated = module_instance.with_examples(examples)

    updated.named_predictors.to_h.each do |_name, predictor|
      expect(predictor.example_calls.last).to eq(examples)
    end

    module_instance.named_predictors.to_h.each do |_name, predictor|
      expect(predictor.example_calls).to be_empty
    end
  end
end
