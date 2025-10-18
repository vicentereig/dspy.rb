# frozen_string_literal: true

require 'spec_helper'
require 'gepa'
require 'gepa/core/engine'

RSpec.describe GEPA::Core::Engine do
  class TestProposer
    def initialize(proposals)
      @proposals = proposals
    end

    def propose(_state)
      @proposals.shift
    end
  end

  let(:logger) { instance_double('Logger', log: nil) }
  let(:experiment_tracker) { instance_double('Tracker', log_metrics: nil) }
  let(:telemetry) do
    double('Telemetry').tap do |tel|
      allow(tel).to receive(:with_span) { |_operation, _attrs, &block| block.call }
    end
  end

  let(:seed_candidate) { { 'instruction' => 'base' } }
  let(:valset) { [{}] }
  let(:evaluator) do
    proc do |_dataset, candidate|
      instruction = candidate['instruction']
      [[instruction], [instruction.length.to_f]]
    end
  end

  it 'accepts proposals and records telemetry spans' do
    proposal = GEPA::Proposer::CandidateProposal.new(
      candidate: { 'instruction' => 'improved' },
      parent_program_ids: [0],
      subsample_indices: [0],
      subsample_scores_before: [0.4],
      subsample_scores_after: [0.6]
    )

    proposer = TestProposer.new([proposal, nil])

    call_order = []
    allow(telemetry).to receive(:with_span) do |operation, attrs = {}, &block|
      call_order << [operation, attrs]
      block.call
    end

    engine = described_class.new(
      run_dir: nil,
      evaluator: evaluator,
      valset: valset,
      seed_candidate: seed_candidate,
      max_metric_calls: 10,
      perfect_score: 1.0,
      seed: 0,
      reflective_proposer: proposer,
      merge_proposer: nil,
      logger: logger,
      experiment_tracker: experiment_tracker,
      telemetry: telemetry,
      track_best_outputs: false,
      display_progress_bar: false
    )

    state = engine.run

    expect(state.program_candidates.size).to eq(2)
    expect(state.program_candidates.last['instruction']).to eq('improved')
    expect(call_order.map(&:first)).to include('gepa.engine.run', 'gepa.engine.iteration', 'gepa.engine.full_evaluation')
  end
end

