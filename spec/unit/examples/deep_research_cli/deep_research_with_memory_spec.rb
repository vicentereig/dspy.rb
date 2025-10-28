# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_research"
require "dspy/deep_research_with_memory"

RSpec.describe DSPy::DeepResearchWithMemory do
  SectionResult = DSPy::DeepResearch::Module::SectionResult
  Result = DSPy::DeepResearch::Module::Result

  class SequencedDeepResearch < DSPy::Module
    attr_reader :call_args, :instruction_calls, :example_calls

    def initialize(results)
      super()
      @results = results.dup
      @call_args = []
      @instruction_calls = []
      @example_calls = []
    end

    def forward_untyped(**kwargs)
      @call_args << kwargs
      @results.shift || @results.last
    end

    def with_instruction(instruction)
      dup = self.class.new(@results.dup)
      dup.instance_variable_set(:@instruction_calls, instruction_calls + [instruction])
      dup.instance_variable_set(:@example_calls, example_calls.dup)
      dup
    end

    def with_examples(examples)
      dup = self.class.new(@results.dup)
      dup.instance_variable_set(:@instruction_calls, instruction_calls.dup)
      dup.instance_variable_set(:@example_calls, example_calls + [examples])
      dup
    end
  end

  let(:sections) do
    [
      SectionResult.new(
        identifier: "sec-1",
        title: "Origins",
        draft: "Origins draft",
        citations: ["https://example.com/origins"],
        attempt: 0
      )
    ]
  end

  let(:first_result) do
    Result.new(
      report: "Origins report",
      sections: sections,
      citations: ["https://example.com/origins"]
    )
  end

  let(:second_result) do
    Result.new(
      report: "Impact report",
      sections: [
        SectionResult.new(
          identifier: "sec-2",
          title: "Impact",
          draft: "Impact draft",
          citations: ["https://example.com/impact"],
          attempt: 0
        )
      ],
      citations: ["https://example.com/impact"]
    )
  end

  let(:third_result) do
    Result.new(
      report: "Future report",
      sections: [
        SectionResult.new(
          identifier: "sec-3",
          title: "Future",
          draft: "Future draft",
          citations: ["https://example.com/future"],
          attempt: 1
        )
      ],
      citations: ["https://example.com/future"]
    )
  end

  let(:inner_module) { SequencedDeepResearch.new([first_result, second_result, third_result]) }

  subject(:supervisor) do
    described_class.new(
      deep_research_module: inner_module,
      memory_limit: 2
    )
  end

  before do
    allow(DSPy).to receive(:event).and_call_original
  end

  describe "#call" do
    it "passes prior memory entries to the deep research module" do
      supervisor.call(brief: "Tell me about origins")
      supervisor.call(brief: "Tell me about impact")

      expect(inner_module.call_args.first[:memory]).to eq([])
      expect(inner_module.call_args[1][:memory].map { |entry| entry[:brief] }).to eq(["Tell me about origins"])
    end

    it "stores compact memory entries and enforces the configured limit" do
      supervisor.call(brief: "Tell me about origins")
      supervisor.call(brief: "Tell me about impact")
      supervisor.call(brief: "Tell me about the future")

      briefs = supervisor.memory.map { |entry| entry[:brief] }
      expect(briefs).to eq(["Tell me about impact", "Tell me about the future"])

      expect(supervisor.memory.first).to include(
        report: "Impact report",
        citations: ["https://example.com/impact"],
        sections: second_result.sections
      )
    end

    it "emits a memory updated event with the latest summary" do
      supervisor.call(brief: "Tell me about origins")

      expect(DSPy).to have_received(:event).with(
        "deep_research.memory.updated",
        hash_including(size: 1, last_brief: "Tell me about origins")
      )
    end
  end

  describe "#with_instruction" do
    it "propagates instructions to the inner module and keeps existing memory" do
      supervisor.call(brief: "Tell me about origins")

      updated = supervisor.with_instruction("Keep it concise")

      expect(updated).to be_a(described_class)
      expect(updated.memory).to eq(supervisor.memory)
      expect(updated.deep_research_module.instruction_calls).to include("Keep it concise")
    end
  end

  describe "#with_examples" do
    it "propagates few-shot examples to the inner module" do
      examples = [
        DSPy::FewShotExample.new(
          input: { brief: "example" },
          output: { report: "result" },
          reasoning: "notes"
        )
      ]

      updated = supervisor.with_examples(examples)

      expect(updated.deep_research_module.example_calls).to include(examples)
    end
  end

  describe "#named_predictors" do
    it "exposes the deep research module for optimizers" do
      expect(supervisor.named_predictors).to eq([["deep_research", inner_module]])
    end
  end
end
