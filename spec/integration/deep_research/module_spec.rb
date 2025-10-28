# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_research"
require "ostruct"

RSpec.describe DSPy::DeepResearch::Module do
  let(:search_client) { DSPy::DeepSearch::Clients::ExaClient.new }

  let(:deep_search_factory) do
    lambda do
      seed_predictor = Class.new do
        def call(question:)
          OpenStruct.new(query: question)
        end
      end.new

      reader_predictor = Class.new do
        def call(url:)
          OpenStruct.new(notes: [])
        end
      end.new

      reason_predictor = Class.new do
        def call(question:, insights:)
          if insights.size >= 6
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

      DSPy::DeepSearch::Module.new(
        token_budget: DSPy::DeepSearch::TokenBudget.new(limit: 12_000),
        seed_predictor: seed_predictor,
        reader_predictor: reader_predictor,
        reason_predictor: reason_predictor,
        search_client: search_client
      )
    end
  end

  let(:planner) do
    Class.new do
      def call(brief:, mode: DSPy::DeepResearch::Module::ResearchMode::Medium)
        sections = [
          DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec.new(
            identifier: "sec-overview",
            title: "Overview",
            prompt: "#{brief} overview",
            token_budget: 4_000
          ),
          DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec.new(
            identifier: "sec-architecture",
            title: "Architecture",
            prompt: "#{brief} architecture",
            token_budget: 4_000
          )
        ]

        case mode
        when DSPy::DeepResearch::Module::ResearchMode::Light
          sections = sections.first(1)
        when DSPy::DeepResearch::Module::ResearchMode::Hard, DSPy::DeepResearch::Module::ResearchMode::Ultra
          sections << DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec.new(
            identifier: "sec-future",
            title: "Future Work",
            prompt: "#{brief} future work",
            token_budget: 4_000
          )
        end

        OpenStruct.new(sections: sections)
      end
    end.new
  end

  let(:synthesizer) do
    Class.new do
      def call(brief:, section:, answer:, notes:, citations:)
        OpenStruct.new(
          draft: "#{section.title}: #{notes.first(2).join(' ')}",
          citations: citations.first(5)
        )
      end
    end.new
  end

  let(:qa_reviewer) do
    Class.new do
      def call(brief:, section:, draft:, notes:, citations:, attempt:)
        OpenStruct.new(
          status: DSPy::DeepResearch::Signatures::QAReview::Status::Approved,
          follow_up_prompt: nil
        )
      end
    end.new
  end

  let(:reporter) do
    Class.new do
      def call(brief:, sections:)
        body = sections.map(&:draft).join("\n")
        OpenStruct.new(report: body, citations: sections.flat_map(&:citations))
      end
    end.new
  end

  subject(:module_instance) do
    described_class.new(
      planner: planner,
      deep_search_factory: deep_search_factory,
      synthesizer: synthesizer,
      qa_reviewer: qa_reviewer,
      reporter: reporter,
      max_section_attempts: 2
    )
  end

  it "aggregates DeepSearch runs into a coherent report", :vcr do
    result = module_instance.call(brief: "Jina DeepSearch DeepResearch")

    expect(result.sections.length).to eq(2)
    expect(result.sections.first.citations).not_to be_empty
    expect(result.citations).not_to be_empty
    expect(result.report).to include("Overview:", "Architecture:")
  end

  it "produces a partial report when DeepSearch exhausts the token budget" do
    partial_factory = lambda do
      Class.new(DSPy::Module) do
        def forward_untyped(question:)
          DSPy::DeepSearch::Module::Result.new(
            answer: "Partial answer for #{question}",
            notes: ["Fragmentary insight for #{question}"],
            citations: ["https://partial.example.com/#{question.tr(' ', '-')}"],
            budget_exhausted: true,
            warning: "Token budget exhausted"
          )
        end
      end.new
    end

    partial_instance = described_class.new(
      planner: planner,
      deep_search_factory: partial_factory,
      synthesizer: synthesizer,
      qa_reviewer: qa_reviewer,
      reporter: reporter,
      max_section_attempts: 1
    )

    result = partial_instance.call(
      brief: "Token constrained topic",
      mode: DSPy::DeepResearch::Module::ResearchMode::Light
    )

    expect(result.sections.length).to eq(1)
    expect(result.sections.first.status).to eq(DSPy::DeepResearch::Module::SectionResult::Status::Partial)
    expect(result.sections.first.draft).to include("Fragmentary insight")
    expect(result.report).to include("Fragmentary insight")
  end
end
