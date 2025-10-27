# frozen_string_literal: true

require "spec_helper"
require "dspy/deep_search"

RSpec.describe DSPy::DeepSearch::GapQueue do
  subject(:queue) { described_class.new }

  it "enqueues unique items while preserving FIFO order" do
    queue.enqueue("first")
    queue.enqueue("second")
    queue.enqueue("first")

    expect(queue.size).to eq(2)
    expect(queue.dequeue).to eq("first")
    expect(queue.dequeue).to eq("second")
  end

  it "reports when empty" do
    expect(queue).to be_empty

    queue.enqueue("gap")

    expect(queue).not_to be_empty
  end

  it "raises when dequeuing an empty queue" do
    expect { queue.dequeue }.to raise_error(DSPy::DeepSearch::GapQueue::Empty)
  end
end
