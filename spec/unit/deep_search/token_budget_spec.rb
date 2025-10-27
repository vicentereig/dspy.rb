# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_search"

RSpec.describe DSPy::DeepSearch::TokenBudget do
  subject(:budget) { described_class.new(limit: 100) }

  describe "#track!" do
    it "allows usage while below the limit" do
      expect { budget.track!(prompt_tokens: 40, completion_tokens: 10) }.not_to raise_error
    end

    it "raises when cumulative usage meets the configured limit" do
      budget.track!(prompt_tokens: 60, completion_tokens: 20)

      expect do
        budget.track!(prompt_tokens: 10, completion_tokens: 10)
      end.to raise_error(DSPy::DeepSearch::TokenBudget::Exceeded)
    end

    it "tracks cumulative usage" do
      budget.track!(prompt_tokens: 30, completion_tokens: 20)
      budget.track!(prompt_tokens: 10, completion_tokens: 5)

      expect(budget.total_tokens).to eq(65)
    end
  end
end
