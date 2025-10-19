# frozen_string_literal: true

require 'spec_helper'
require 'gepa/proposer/merge_proposer'
require 'gepa/core/state'

RSpec.describe GEPA::Proposer::MergeProposer do
  let(:logger) { instance_double('Logger', log: nil) }
  let(:telemetry) { instance_double('Telemetry', with_span: nil) }
  let(:valset) { Array.new(2) { |i| { id: i } } }

  def subscores_for(candidate)
    [
      candidate.fetch('thought', '').include?('better') ? 0.8 : 0.5,
      candidate.fetch('planner', '').include?('better') ? 0.9 : 0.4
    ]
  end

  let(:evaluator) do
    lambda do |dataset, candidate|
      outputs = dataset.map { |_example| candidate.dup }
      [outputs, subscores_for(candidate)]
    end
  end

  let(:merge_proposer) do
    described_class.new(
      logger: logger,
      valset: valset,
      evaluator: evaluator,
      use_merge: true,
      max_merge_invocations: 3,
      rng: Random.new(0),
      telemetry: telemetry
    )
  end

  def build_state
    seed_candidate = { 'thought' => 'base_thought', 'planner' => 'base_plan' }
    base_scores = subscores_for(seed_candidate)
    base_outputs = Array.new(2) { |i| { seed: i } }

    state = GEPA::Core::State.new(seed_candidate, [base_outputs, base_scores], track_best_outputs: false)
    state.num_full_ds_evals = 1
    state.total_num_evals = base_scores.length
    state.full_program_trace << {}

    # Candidate 1 improves the first predictor
    cand1 = { 'thought' => 'better_thought', 'planner' => 'base_plan' }
    scores1 = subscores_for(cand1)
    state.update_state_with_new_program(
      [0],
      cand1,
      scores1.sum / scores1.length,
      Array.new(2) { { cand: 1 } },
      scores1,
      nil,
      state.total_num_evals
    )

    # Candidate 2 improves the second predictor
    cand2 = { 'thought' => 'base_thought', 'planner' => 'better_plan' }
    scores2 = subscores_for(cand2)
    state.update_state_with_new_program(
      [0],
      cand2,
      scores2.sum / scores2.length,
      Array.new(2) { { cand: 2 } },
      scores2,
      nil,
      state.total_num_evals
    )

    state
  end

  it 'queues merge attempts when requested' do
    expect { merge_proposer.schedule_if_needed }
      .to change(merge_proposer, :merges_due).by(1)
  end

  it 'proposes a merged candidate when two descendants share a better component' do
    state = build_state
    state.i = 2
    merge_proposer.merges_due = 1
    merge_proposer.last_iter_found_new_program = true

    proposal = merge_proposer.propose(state)

    expect(proposal).not_to be_nil
    expect(proposal.tag).to eq('merge')
    expect(proposal.candidate).to eq(
      'thought' => 'better_thought',
      'planner' => 'better_plan'
    )

    expect(state.full_program_trace.last[:merged]).to be(true)
    expect(proposal.parent_program_ids).to include(1, 2)
    expect(proposal.subsample_scores_before).to all(be > 0.0)
    expect(proposal.subsample_scores_after).to all(be_a(Float))
  end
end
