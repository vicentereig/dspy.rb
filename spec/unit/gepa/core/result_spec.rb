# frozen_string_literal: true

require 'spec_helper'
require 'gepa/core/result'
require 'gepa/core/state'

RSpec.describe GEPA::Core::Result do
  let(:seed_candidate) { { 'instruction' => 'Initial instruction' } }
  let(:state) { GEPA::Core::State.new(seed_candidate, [['out'], [1.0]], track_best_outputs: true) }

  describe '.from_state' do
    it 'builds a result snapshot preserving candidates and metadata' do
      result = described_class.from_state(state, run_dir: '/tmp/gepa', seed: 42)

      expect(result.num_candidates).to eq(1)
      expect(result.best_candidate).to eq(seed_candidate)
      expect(result.run_dir).to eq('/tmp/gepa')
      expect(result.seed).to eq(42)
      expect(result.per_val_instance_best_candidates.first).to eq([0])
    end
  end

  describe '#to_h' do
    it 'serializes to hashes and arrays without mutating internal state' do
      result = described_class.from_state(state)
      hash = result.to_h

      expect(hash[:candidates]).to eq([seed_candidate])
      expect(hash[:per_val_instance_best_candidates]).to eq([[0]])
      expect(hash[:best_idx]).to eq(0)
    end
  end
end
