# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'set'
require 'gepa/core/state'

RSpec.describe GEPA::Core::State do
  let(:seed_candidate) { { 'instruction' => 'Initial instruction' } }
  let(:base_outputs) { ['out-1', 'out-2'] }
  let(:base_scores) { [0.5, 0.6] }
  let(:state) { described_class.new(seed_candidate, [base_outputs, base_scores], track_best_outputs: true) }

  describe '#initialize' do
    it 'bootstraps baseline structures' do
      expect(state.program_candidates).to eq([seed_candidate])
      expect(state.program_full_scores_val_set).to eq([0.55])
      expect(state.program_at_pareto_front_valset).to all(eq(Set[0]))
      expect(state.best_outputs_valset).to eq([[ [0, 'out-1'] ], [ [0, 'out-2'] ]])
    end
  end

  describe '#consistent?' do
    it 'returns true for a freshly initialized state' do
      expect(state.consistent?).to be(true)
    end
  end

  describe '#update_state_with_new_program' do
    it 'appends the new program and updates pareto structures' do
      Dir.mktmpdir do |dir|
        new_program = { 'instruction' => 'Improved instruction' }
        val_outputs = ['out-new-1', 'out-new-2']
        val_subscores = [0.7, 0.6]

        new_idx, best_idx = state.update_state_with_new_program(
          [0],
          new_program,
          0.65,
          val_outputs,
          val_subscores,
          dir,
          3
        )

        expect(new_idx).to eq(1)
        expect(best_idx).to eq(1)
        expect(state.program_candidates.last).to eq(new_program)
        expect(state.pareto_front_valset).to eq([0.7, 0.6])
        expect(state.program_at_pareto_front_valset[0]).to eq(Set[1])

        path = File.join(dir, 'generated_best_outputs_valset', 'task_0')
        expect(Dir.children(path)).to_not be_empty
      end
    end
  end

  describe '.initialize_gepa_state' do
    it 'creates a new state when no artifacts exist' do
      logger = instance_double('Logger', log: nil)
      valset_evaluator = ->(_) { [base_outputs, base_scores] }

      Dir.mktmpdir do |dir|
        result = described_class.initialize_gepa_state(
          run_dir: dir,
          logger: logger,
          seed_candidate: seed_candidate,
          valset_evaluator: valset_evaluator,
          track_best_outputs: false
        )

        expect(result).to be_a(described_class)
        expect(result.num_full_ds_evals).to eq(1)
        expect(result.total_num_evals).to eq(2)
      end
    end
  end
end
