# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Evals parallel program cloning' do
  class ParallelCloneSignature < DSPy::Signature
    description 'Parallel clone signature'

    input do
      const :value, Integer
    end

    output do
      const :value, Integer
    end
  end

  class ParallelCloneProgram < DSPy::Module
    class << self
      def reset_seen!
        @seen_ids = []
        @mutex = Mutex.new
      end

      def record_seen(id)
        @mutex.synchronize { @seen_ids << id }
      end

      def seen_ids
        @seen_ids
      end
    end

    reset_seen!

    def forward(value:)
      self.class.record_seen(object_id)
      value
    end
  end

  it 'uses per-thread clones when evaluating in parallel' do
    program = ParallelCloneProgram.new
    ParallelCloneProgram.reset_seen!

    examples = (1..4).map do |value|
      DSPy::Example.new(
        signature_class: ParallelCloneSignature,
        input: { value: value },
        expected: { value: value }
      )
    end

    evaluator = DSPy::Evals.new(program, num_threads: 2)
    evaluator.evaluate(examples, display_progress: false)

    seen_ids = ParallelCloneProgram.seen_ids
    expect(seen_ids.uniq.length).to be > 1
    expect(seen_ids).not_to include(program.object_id)
  end
end
