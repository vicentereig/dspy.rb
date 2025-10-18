# frozen_string_literal: true

require 'spec_helper'
require 'set'
require 'gepa/utils/pareto'

RSpec.describe GEPA::Utils::Pareto do
  describe '.idxmax' do
    it 'returns the index of the maximum element' do
      expect(described_class.idxmax([0.2, 0.9, 0.8])).to eq(1)
    end

    it 'raises when list is empty' do
      expect { described_class.idxmax([]) }.to raise_error(ArgumentError)
    end
  end

  describe '.remove_dominated_programs' do
    it 'removes dominated programs based on scores' do
      fronts = [Set[0, 1], Set[1, 2]]
      scores = { 0 => 0.4, 1 => 0.8, 2 => 0.6 }

      cleaned = described_class.remove_dominated_programs(fronts, scores: scores)

      expect(cleaned).to all(eq([1]))
    end
  end

  describe '.find_dominator_programs' do
    it 'returns unique dominators across fronts' do
      fronts = [Set[0, 1], Set[1, 2]]
      scores = { 0 => 0.4, 1 => 0.8, 2 => 0.6 }

      expect(described_class.find_dominator_programs(fronts, scores)).to eq([1])
    end
  end

  describe '.select_program_candidate_from_pareto_front' do
    it 'samples using weighted frequency with deterministic rng' do
      fronts = [Set[0, 1], Set[1, 2]]
      scores = { 0 => 0.4, 1 => 0.8, 2 => 0.6 }
      rng = Random.new(123)

      expect(
        described_class.select_program_candidate_from_pareto_front(fronts, scores, rng)
      ).to eq(1)
    end

    it 'raises when pareto front empty' do
      expect do
        described_class.select_program_candidate_from_pareto_front([], {}, Random.new)
      end.to raise_error(ArgumentError)
    end
  end
end
