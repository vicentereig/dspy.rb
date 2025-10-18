# frozen_string_literal: true

require 'spec_helper'
require 'gepa'
require 'gepa/proposer/reflective_mutation/reflective_mutation'

RSpec.describe GEPA::Proposer::ReflectiveMutationProposer do
  let(:logger) { instance_double('Logger', log: nil) }
  let(:trainset) { [{ input: 'question?' }] }
  let(:adapter) { instance_double('Adapter') }
  let(:candidate_selector) { instance_double('CandidateSelector') }
  let(:module_selector) { instance_double('ModuleSelector') }
  let(:batch_sampler) { instance_double('BatchSampler') }
  let(:experiment_tracker) { instance_double('Tracker', log_metrics: nil) }
  let(:telemetry) { double('Telemetry') }

  before do
    allow(telemetry).to receive(:with_span) { |_operation, _attrs, &block| block.call }
  end

  def build_state
    GEPA::Core::State.new({ 'instruction' => 'Initial' }, [[{ output: 'a' }], [0.5]])
  end

  it 'returns candidate proposal with updated instruction and telemetry spans' do
    state = build_state

    allow(candidate_selector).to receive(:select_candidate_idx).and_return(0)
    allow(batch_sampler).to receive(:next_minibatch_indices).and_return([0])
    allow(module_selector).to receive(:select_modules).and_return(['instruction'])

    eval_batch = GEPA::Core::EvaluationBatch.new(
      outputs: ['answer'],
      scores: [0.4],
      trajectories: ['trace']
    )
    new_eval_batch = GEPA::Core::EvaluationBatch.new(
      outputs: ['answer2'],
      scores: [0.6],
      trajectories: nil
    )

    allow(adapter).to receive(:evaluate).with(trainset, anything, any_args)
    allow(adapter).to receive(:evaluate).and_return(eval_batch, new_eval_batch)
    allow(adapter).to receive(:make_reflective_dataset).and_return({ 'instruction' => [{ 'Feedback' => 'improve' }] })
    allow(adapter).to receive(:propose_new_texts).and_return({ 'instruction' => 'Improved' })

    proposer = described_class.new(
      logger: logger,
      trainset: trainset,
      adapter: adapter,
      candidate_selector: candidate_selector,
      module_selector: module_selector,
      batch_sampler: batch_sampler,
      perfect_score: 1.0,
      skip_perfect_score: true,
      experiment_tracker: experiment_tracker,
      telemetry: telemetry
    )

    proposal = proposer.propose(state)

    expect(proposal).not_to be_nil
    expect(proposal.candidate['instruction']).to eq('Improved')
    expect(proposal.subsample_indices).to eq([0])
    expect(proposal.subsample_scores_before).to eq([0.4])
    expect(proposal.subsample_scores_after).to eq([0.6])
  end

  it 'skips when scores are perfect and skip flag enabled' do
    state = build_state

    allow(candidate_selector).to receive(:select_candidate_idx).and_return(0)
    allow(batch_sampler).to receive(:next_minibatch_indices).and_return([0])
    allow(module_selector).to receive(:select_modules).and_return(['instruction'])

    perfect_batch = GEPA::Core::EvaluationBatch.new(
      outputs: ['answer'],
      scores: [1.0],
      trajectories: ['trace']
    )

    allow(adapter).to receive(:evaluate).and_return(perfect_batch)

    proposer = described_class.new(
      logger: logger,
      trainset: trainset,
      adapter: adapter,
      candidate_selector: candidate_selector,
      module_selector: module_selector,
      batch_sampler: batch_sampler,
      perfect_score: 1.0,
      skip_perfect_score: true,
      experiment_tracker: experiment_tracker,
      telemetry: telemetry
    )

    expect(proposer.propose(state)).to be_nil
  end
end

