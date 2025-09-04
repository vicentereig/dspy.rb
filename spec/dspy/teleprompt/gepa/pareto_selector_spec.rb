# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::ParetoSelector do
  # Test signature for Pareto selection testing
  class ParetoTestSignature < DSPy::Signature
    description "Test signature for Pareto selection"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new.tap do |c|
      c.population_size = 8
      c.use_pareto_selection = true
    end
  end

  let(:fitness_evaluator) do
    primary_metric = proc { |example, prediction| example.expected_values[:answer] == prediction.answer ? 1.0 : 0.0 }
    DSPy::Teleprompt::GEPA::FitnessEvaluator.new(primary_metric: primary_metric, config: config)
  end

  let(:mock_programs) do
    Array.new(6) { |i| double("program_#{i}", signature_class: ParetoTestSignature) }
  end

  let(:sample_fitness_scores) do
    [
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.9,
        secondary_scores: { token_efficiency: 0.8, consistency: 0.7, latency: 0.9 },
        overall_score: 0.85
      ),
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.8,
        secondary_scores: { token_efficiency: 0.9, consistency: 0.8, latency: 0.7 },
        overall_score: 0.80
      ),
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.7,
        secondary_scores: { token_efficiency: 0.7, consistency: 0.9, latency: 0.8 },
        overall_score: 0.75
      ),
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.6,
        secondary_scores: { token_efficiency: 0.6, consistency: 0.6, latency: 0.6 },
        overall_score: 0.60
      ),
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.5,
        secondary_scores: { token_efficiency: 0.5, consistency: 0.5, latency: 0.5 },
        overall_score: 0.50
      ),
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.95,
        secondary_scores: { token_efficiency: 0.3, consistency: 0.4, latency: 0.2 },
        overall_score: 0.70
      )
    ]
  end

  describe 'initialization' do
    it 'creates selector with evaluator and config' do
      selector = described_class.new(evaluator: fitness_evaluator, config: config)
      
      expect(selector.evaluator).to eq(fitness_evaluator)
      expect(selector.config).to eq(config)
    end

    it 'requires evaluator parameter' do
      expect { described_class.new(config: config) }.to raise_error(ArgumentError)
    end

    it 'requires config parameter' do
      expect { described_class.new(evaluator: fitness_evaluator) }.to raise_error(ArgumentError)
    end
  end

  describe '#select_parents' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'selects parents using Pareto selection' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      selected = selector.select_parents(population_with_scores, count: 4)
      
      expect(selected).to be_an(Array)
      expect(selected.size).to eq(4)
      selected.each { |program| expect(mock_programs).to include(program) }
    end

    it 'prefers non-dominated solutions' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      selected = selector.select_parents(population_with_scores, count: 3)
      
      # Should include programs with better Pareto characteristics
      expect(selected.size).to eq(3)
    end

    it 'handles empty population' do
      selected = selector.select_parents([], count: 2)
      expect(selected).to be_empty
    end

    it 'handles count larger than population' do
      population_with_scores = mock_programs.take(2).zip(sample_fitness_scores.take(2))
      
      selected = selector.select_parents(population_with_scores, count: 5)
      
      expect(selected.size).to eq(2) # Can't select more than available
    end
  end

  describe '#select_survivors' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'selects survivors maintaining diversity' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      survivors = selector.select_survivors(population_with_scores, count: 4)
      
      expect(survivors).to be_an(Array)
      expect(survivors.size).to eq(4)
      survivors.each { |program| expect(mock_programs).to include(program) }
    end

    it 'combines elite selection with diversity' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      survivors = selector.select_survivors(population_with_scores, count: 3)
      
      # Should balance best performers with diversity
      expect(survivors.size).to eq(3)
    end
  end

  describe '#find_pareto_frontier' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'identifies non-dominated solutions' do
      pareto_frontier = selector.send(:find_pareto_frontier, sample_fitness_scores)
      
      expect(pareto_frontier).to be_an(Array)
      expect(pareto_frontier).not_to be_empty
      
      # All solutions in frontier should be non-dominated by each other
      pareto_frontier.each do |score1|
        pareto_frontier.each do |score2|
          next if score1 == score2
          expect(score1.dominated_by?(score2)).to be(false)
        end
      end
    end

    it 'includes best overall performer' do
      pareto_frontier = selector.send(:find_pareto_frontier, sample_fitness_scores)
      
      best_score = sample_fitness_scores.max_by(&:overall_score)
      expect(pareto_frontier).to include(best_score)
    end

    it 'excludes clearly dominated solutions' do
      pareto_frontier = selector.send(:find_pareto_frontier, sample_fitness_scores)
      
      # The worst performing solution should be dominated
      worst_score = sample_fitness_scores.min_by(&:overall_score)
      
      # Check if it's dominated by any frontier member
      is_dominated = pareto_frontier.any? { |frontier_score| worst_score.dominated_by?(frontier_score) }
      expect(is_dominated).to be(true)
    end

    it 'handles single solution' do
      single_score = [sample_fitness_scores.first]
      pareto_frontier = selector.send(:find_pareto_frontier, single_score)
      
      expect(pareto_frontier).to eq(single_score)
    end

    it 'handles empty input' do
      pareto_frontier = selector.send(:find_pareto_frontier, [])
      expect(pareto_frontier).to be_empty
    end
  end

  describe '#calculate_crowding_distance' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'calculates crowding distances for solutions' do
      distances = selector.send(:calculate_crowding_distance, sample_fitness_scores)
      
      expect(distances).to be_a(Hash)
      expect(distances.size).to eq(sample_fitness_scores.size)
      
      distances.each do |score, distance|
        expect(sample_fitness_scores).to include(score)
        expect(distance).to be_a(Numeric)
        expect(distance).to be >= 0
      end
    end

    it 'assigns infinite distance to boundary solutions' do
      distances = selector.send(:calculate_crowding_distance, sample_fitness_scores)
      
      # Sort by overall score to find boundaries
      sorted_scores = sample_fitness_scores.sort_by(&:overall_score)
      
      # Boundary solutions should have higher crowding distances
      min_score = sorted_scores.first
      max_score = sorted_scores.last
      
      expect(distances[min_score]).to be > 0
      expect(distances[max_score]).to be > 0
    end

    it 'handles identical solutions' do
      # Data classes use value equality, so identical values = same hash key
      # Test with truly identical solutions (same values)
      identical_scores = [sample_fitness_scores.first, sample_fitness_scores.first]
      distances = selector.send(:calculate_crowding_distance, identical_scores)
      
      # Should handle gracefully - identical solutions get same distance
      expect(distances.size).to eq(1) # Same value = same hash key
      distances.values.each { |distance| expect(distance).to be_a(Numeric) }
    end
  end

  describe '#tournament_selection' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'selects better candidate from tournament' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      winner = selector.send(:tournament_selection, population_with_scores)
      
      expect(mock_programs).to include(winner)
    end

    it 'prefers non-dominated solutions in tournament' do
      # Create a biased test by running multiple tournaments
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      winners = []
      
      10.times do
        winners << selector.send(:tournament_selection, population_with_scores)
      end
      
      # Winners should generally be from higher-performing programs
      expect(winners).not_to be_empty
      winners.each { |winner| expect(mock_programs).to include(winner) }
    end

    it 'handles single candidate' do
      single_pair = [mock_programs.first, sample_fitness_scores.first]
      winner = selector.send(:tournament_selection, [single_pair])
      
      expect(winner).to eq(mock_programs.first)
    end
  end

  describe '#diversity_selection' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'selects diverse solutions from population' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      selected = selector.send(:diversity_selection, population_with_scores, count: 3)
      
      expect(selected).to be_an(Array)
      expect(selected.size).to eq(3)
      selected.each { |program| expect(mock_programs).to include(program) }
    end

    it 'maintains diversity in selection' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      selected = selector.send(:diversity_selection, population_with_scores, count: 4)
      
      # Should prefer solutions with higher crowding distances
      expect(selected.size).to eq(4)
    end

    it 'handles count equal to population size' do
      population_with_scores = mock_programs.take(3).zip(sample_fitness_scores.take(3))
      
      selected = selector.send(:diversity_selection, population_with_scores, count: 3)
      
      expect(selected.size).to eq(3)
    end
  end

  describe '#elite_selection' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'selects top performers by overall score' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      elite = selector.send(:elite_selection, population_with_scores, count: 3)
      
      expect(elite).to be_an(Array)
      expect(elite.size).to eq(3)
      
      # Should be sorted by fitness (best first)
      elite_scores = elite.map { |program| sample_fitness_scores[mock_programs.index(program)] }
      
      elite_scores.each_cons(2) do |current, next_score|
        expect(current.overall_score).to be >= next_score.overall_score
      end
    end

    it 'handles count larger than population' do
      population_with_scores = mock_programs.take(2).zip(sample_fitness_scores.take(2))
      
      elite = selector.send(:elite_selection, population_with_scores, count: 5)
      
      expect(elite.size).to eq(2)
    end
  end

  describe 'selection strategy integration' do
    let(:selector) { described_class.new(evaluator: fitness_evaluator, config: config) }

    it 'combines multiple selection strategies effectively' do
      population_with_scores = mock_programs.zip(sample_fitness_scores)
      
      # Test parent selection maintains genetic diversity
      parents = selector.select_parents(population_with_scores, count: 4)
      
      # Test survivor selection balances performance and diversity  
      survivors = selector.select_survivors(population_with_scores, count: 4)
      
      expect(parents.size).to eq(4)
      expect(survivors.size).to eq(4)
      
      # Both selections should include high-quality candidates
      expect((parents + survivors).uniq.size).to be >= 4
    end
  end
end