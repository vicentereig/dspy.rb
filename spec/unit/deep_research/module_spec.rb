# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require "dspy/deep_research"
require "dspy/deep_search"

RSpec.describe DSPy::DeepResearch::Module do
  class StubPredictor < DSPy::Module
    attr_reader :called_with, :instruction_calls, :example_calls

    def initialize(responses = nil, &block)
      super()
      @responses = responses ? Array(responses).dup : []
      @block = block
      @called_with = []
      @instruction_calls = []
      @example_calls = []
    end

    def forward_untyped(**kwargs)
      @called_with << kwargs
      return @block.call(**kwargs) if @block && @responses.empty?

      @responses.shift || @block&.call(**kwargs)
    end

    def with_instruction(instruction)
      dup = self.class.new(@responses.dup, &@block)
      dup.instance_variable_set(:@instruction_calls, instruction_calls + [instruction])
      dup.instance_variable_set(:@example_calls, example_calls.dup)
      dup
    end

    def with_examples(examples)
      dup = self.class.new(@responses.dup, &@block)
      dup.instance_variable_set(:@instruction_calls, instruction_calls.dup)
      dup.instance_variable_set(:@example_calls, example_calls + [examples])
      dup
    end
  end

  let(:outline_sections) do
    [
      DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec.new(
        identifier: "sec-1",
        title: "Origins",
        prompt: "Summarize the origins",
        token_budget: 1_500
      ),
      DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec.new(
        identifier: "sec-2",
        title: "Impact",
        prompt: "Describe the impact",
        token_budget: 1_500
      )
    ]
  end

  let(:planner) do
    StubPredictor.new(OpenStruct.new(sections: outline_sections))
  end

  let(:deep_search_results) do
    [
      DSPy::DeepSearch::Module::Result.new(
        answer: "Origins answer",
        notes: ["Origins note 1", "Origins note 2"],
        citations: ["https://origin.example.com"]
      ),
      DSPy::DeepSearch::Module::Result.new(
        answer: "Origins follow-up",
        notes: ["Origins note 3"],
        citations: ["https://origin:update.example.com"]
      ),
      DSPy::DeepSearch::Module::Result.new(
        answer: "Impact answer",
        notes: ["Impact note"],
        citations: ["https://impact.example.com"]
      )
    ]
  end

  let(:deep_search_builder) do
    queue = deep_search_results.dup
    -> do
      result = queue.shift || queue.last
      Class.new(DSPy::Module) do
        def initialize(result)
          super()
          @result = result
        end

        def forward_untyped(question:)
          @result
        end
      end.new(result)
    end
  end

  let(:synthesizer) do
    StubPredictor.new do |section:, answer:, notes:, citations:, brief:|
      OpenStruct.new(
        draft: "#{section.title}: #{answer}",
        citations: citations
      )
    end
  end

  let(:qa_responses) do
    [
      OpenStruct.new(
        status: DSPy::DeepResearch::Signatures::QAReview::Status::NeedsMoreEvidence,
        follow_up_prompt: "Clarify the origin timeline"
      ),
      OpenStruct.new(
        status: DSPy::DeepResearch::Signatures::QAReview::Status::Approved,
        follow_up_prompt: nil
      ),
      OpenStruct.new(
        status: DSPy::DeepResearch::Signatures::QAReview::Status::Approved,
        follow_up_prompt: nil
      )
    ]
  end

  let(:qa_reviewer) { StubPredictor.new(qa_responses) }

  let(:reporter) do
    StubPredictor.new do |brief:, sections:|
      OpenStruct.new(report: sections.map(&:draft).join("\n"))
    end
  end

  subject(:module_instance) do
    described_class.new(
      planner: planner,
      deep_search_factory: -> { deep_search_builder.call },
      synthesizer: synthesizer,
      qa_reviewer: qa_reviewer,
      reporter: reporter,
      max_section_attempts: 2
    )
  end

  it "produces a report after orchestrating DeepSearch for each section" do
    result = module_instance.call(brief: "Tell me about the topic")

    expect(result.report).to include("Origins:")
    expect(result.sections.map(&:title)).to include("Origins", "Impact")
    expect(result.citations).to include("https://origin.example.com", "https://impact.example.com")
  end

  it "requeues sections when QA requests more evidence" do
    module_instance.call(brief: "Tell me about the topic")

    expect(qa_reviewer.called_with.first[:section].title).to eq("Origins")
    expect(qa_reviewer.called_with[1][:section].title).to eq("Origins")
  end

  it "exposes predictors for optimizers" do
    names = module_instance.named_predictors.map(&:first)
    expect(names).to contain_exactly("planner", "synthesizer", "qa_reviewer", "reporter")
  end

  it "propagates instructions and examples to nested predictors" do
    examples = [DSPy::FewShotExample.new(input: { brief: "a" }, output: { report: "b" }, reasoning: "c")]
    updated = module_instance.with_instruction("Tighten tone").with_examples(examples)

    updated.named_predictors.each do |_name, predictor|
      expect(predictor.instruction_calls).to include("Tighten tone")
      expect(predictor.example_calls).to include(examples)
    end
  end

  it "emits instrumentation events across the section lifecycle" do
    events = []
    allow(DSPy).to receive(:event) do |name, attrs|
      events << [name, attrs]
    end

    module_instance.call(brief: "Tell me about the topic")

    event_names = events.map(&:first)
    expect(event_names).to include(
      "deep_research.section.started",
      "deep_research.section.qa_retry",
      "deep_research.report.ready"
    )

    started = events.find { |name, _| name == "deep_research.section.started" }
    expect(started[1]).to include(identifier: "sec-1", attempt: 0)

    qa_retry = events.find { |name, _| name == "deep_research.section.qa_retry" }
    expect(qa_retry[1]).to include(identifier: "sec-1", follow_up_prompt: "Clarify the origin timeline")

    report_ready = events.find { |name, _| name == "deep_research.report.ready" }
    expect(report_ready[1]).to include(section_count: 2)
  end
end
