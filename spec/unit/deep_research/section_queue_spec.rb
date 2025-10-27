# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_research"

RSpec.describe DSPy::DeepResearch::SectionQueue do
  let(:section_a) do
    DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec.new(
      identifier: "sec-1",
      title: "Introduction",
      prompt: "Explain the background of the topic",
      token_budget: 2_000
    )
  end

  let(:section_b) do
    DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec.new(
      identifier: "sec-2",
      title: "Analysis",
      prompt: "Analyse recent developments",
      token_budget: 2_500
    )
  end

  subject(:queue) { described_class.new }

  it "returns sections in FIFO order" do
    queue.enqueue(section_a)
    queue.enqueue(section_b)

    expect(queue.dequeue).to eq(section_a)
    expect(queue.dequeue).to eq(section_b)
  end

  it "tracks pending work" do
    expect(queue).to be_empty
    queue.enqueue(section_a)
    expect(queue).not_to be_empty
    queue.dequeue
    expect(queue).to be_empty
  end

  it "enqueues follow-up work ahead of the backlog" do
    queue.enqueue(section_a)
    queue.enqueue(section_b)

    follow_up = queue.enqueue_follow_up(section_a, prompt: "Clarify background timeline")

    expect(follow_up.prompt).to eq("Clarify background timeline")
    expect(queue.dequeue).to eq(follow_up)
    expect(queue.dequeue).to eq(section_b)
  end
end
