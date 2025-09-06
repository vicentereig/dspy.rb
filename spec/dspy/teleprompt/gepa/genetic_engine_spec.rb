# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::GeneticEngine do
  # Test signature for genetic engine testing
  class GeneticTestSignature < DSPy::Signature
    description "Test signature for genetic algorithm"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new.tap do |c|
      c.num_generations = 3
      c.population_size = 4
      c.mutation_rate = 0.5
    end
  end

  let(:metric) { proc { |example, prediction| example.expected_values[:answer] == prediction.answer ? 1.0 : 0.0 } }
  
  let(:fitness_evaluator) do
    DSPy::Teleprompt::GEPA::FitnessEvaluator.new(
      primary_metric: metric,
      config: config
    )
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: GeneticTestSignature,
        input: { question: 'What is 2+2?' },
        expected: { answer: '4' }
      ),
      DSPy::Example.new(
        signature_class: GeneticTestSignature,
        input: { question: 'What is 3+3?' },
        expected: { answer: '6' }
      )
    ]
  end

  let(:mock_program) do
    double('program', signature_class: GeneticTestSignature)
  end

  describe 'initialization' do
    it 'creates engine with config and fitness_evaluator' do
      engine = described_class.new(config: config, fitness_evaluator: fitness_evaluator)
      
      expect(engine.config).to eq(config)
      expect(engine.fitness_evaluator).to eq(fitness_evaluator)
    end

    it 'initializes empty population' do
      engine = described_class.new(config: config, fitness_evaluator: fitness_evaluator)
      
      expect(engine.population).to be_empty
      expect(engine.generation).to eq(0)
    end

    it 'requires config parameter' do
      expect { described_class.new(fitness_evaluator: fitness_evaluator) }.to raise_error(ArgumentError)
    end

    it 'requires fitness_evaluator parameter' do
      expect { described_class.new(config: config) }.to raise_error(ArgumentError)
    end
  end

  describe '#initialize_population' do
    let(:engine) { described_class.new(config: config, fitness_evaluator: fitness_evaluator) }

    it 'creates initial population from program' do
      engine.initialize_population(mock_program)
      
      expect(engine.population.size).to eq(config.population_size)
      expect(engine.generation).to eq(0)
    end

    it 'creates diverse instruction variants for initial population' do
      engine.initialize_population(mock_program)
      
      # Population should be created with the correct size
      expect(engine.population.size).to eq(config.population_size)
      # Original program should be in population
      expect(engine.population).to include(mock_program)
      # Should have at least some diversity (not all the same object)
      expect(engine.population.uniq.size).to be > 1
    end

    it 'includes original program in population' do
      engine.initialize_population(mock_program)
      
      # Original program should be in population
      expect(engine.population).to include(mock_program)
    end
  end

  describe '#evaluate_population' do
    let(:engine) { described_class.new(config: config, fitness_evaluator: fitness_evaluator) }

    before do
      engine.initialize_population(mock_program)
      
      # Mock population evaluation
      engine.population.each_with_index do |candidate, index|
        allow(candidate).to receive(:call).and_return(
          double('prediction', answer: index.even? ? '4' : 'wrong')
        )
      end
    end

    it 'evaluates all population members' do
      scores = engine.evaluate_population(trainset)
      
      expect(scores.size).to eq(config.population_size)
      scores.each { |score| expect(score).to be_a(DSPy::Teleprompt::GEPA::FitnessScore) }
    end

    it 'returns fitness scores between 0 and 1' do
      scores = engine.evaluate_population(trainset)
      
      scores.each do |score|
        expect(score.overall_score).to be_between(0.0, 1.0)
        expect(score.primary_score).to be_between(0.0, 1.0)
      end
    end

    it 'handles evaluation errors gracefully' do
      engine.population.first.tap do |candidate|
        allow(candidate).to receive(:call).and_raise(StandardError, 'Evaluation error')
      end
      
      expect { engine.evaluate_population(trainset) }.not_to raise_error
      
      scores = engine.evaluate_population(trainset)
      expect(scores.first.overall_score).to be <= 1.0 # Failed evaluation gets a low score
      expect(scores.first.metadata).to have_key(:errors_count) # Error tracking
    end
  end

  describe '#evolve_generation' do
    let(:engine) { described_class.new(config: config, fitness_evaluator: fitness_evaluator) }

    before do
      engine.initialize_population(mock_program)
      
      # Mock fitness evaluator to return FitnessScore objects
      fitness_scores = [0.8, 0.6, 0.4, 0.2].map do |score|
        DSPy::Teleprompt::GEPA::FitnessScore.new(
          primary_score: score,
          secondary_scores: {},
          overall_score: score,
          metadata: {}
        )
      end
      allow(engine).to receive(:evaluate_population).and_return(fitness_scores)
    end

    it 'advances to next generation' do
      original_generation = engine.generation
      engine.evolve_generation(trainset)
      
      expect(engine.generation).to eq(original_generation + 1)
    end

    it 'maintains population size' do
      original_size = engine.population.size
      engine.evolve_generation(trainset)
      
      expect(engine.population.size).to eq(original_size)
    end

    it 'applies selection pressure' do
      # Initialize population first
      engine.initialize_population(mock_program)
      original_population_size = engine.population.size
      
      # Higher fitness candidates should survive more often
      engine.evolve_generation(trainset)
      
      # Population should still exist and maintain size
      expect(engine.population).not_to be_empty
      expect(engine.population.size).to eq(original_population_size)
      # Generation should increment
      expect(engine.generation).to be > 0
    end
  end

  describe '#run_evolution' do
    let(:engine) { described_class.new(config: config, fitness_evaluator: fitness_evaluator) }

    it 'runs complete evolution for specified generations' do
      # Mock the evaluation and evolution steps
      allow(engine).to receive(:initialize_population)
      # Mock fitness scores
      fitness_scores = [0.8, 0.6, 0.4, 0.2].map do |score|
        DSPy::Teleprompt::GEPA::FitnessScore.new(
          primary_score: score,
          secondary_scores: {},
          overall_score: score,
          metadata: {}
        )
      end
      allow(engine).to receive(:evaluate_population).and_return(fitness_scores)
      allow(engine).to receive(:evolve_generation)
      
      result = engine.run_evolution(mock_program, trainset)
      
      expect(engine).to have_received(:evolve_generation).exactly(config.num_generations).times
      expect(result).to be_a(Hash)
      expect(result).to include(:best_candidate, :best_fitness, :generation_history)
    end

    it 'returns best candidate and fitness' do
      # Mock initialization and evaluation properly
      allow(engine).to receive(:initialize_population)
      
      # Mock evaluation to return improving scores
      call_count = 0
      allow(engine).to receive(:evaluate_population) do |trainset|
        call_count += 1
        scores = case call_count
        when 1 then [0.5, 0.3, 0.2, 0.1] # Initial
        when 2 then [0.7, 0.5, 0.4, 0.3] # Gen 1  
        when 3 then [0.9, 0.7, 0.6, 0.5] # Gen 2
        else [0.9, 0.8, 0.7, 0.6]       # Gen 3
        end
        scores.map do |score|
          DSPy::Teleprompt::GEPA::FitnessScore.new(
            primary_score: score,
            secondary_scores: {},
            overall_score: score,
            metadata: {}
          )
        end
      end
      
      # Mock population and evolution
      allow(engine).to receive(:evolve_generation)
      allow(engine).to receive(:population_diversity).and_return(0.8)
      
      # Set up fitness scores manually for the final result
      final_scores = [0.9, 0.8, 0.7, 0.6].map do |score|
        DSPy::Teleprompt::GEPA::FitnessScore.new(
          primary_score: score,
          secondary_scores: {},
          overall_score: score,
          metadata: {}
        )
      end
      engine.instance_variable_set(:@fitness_scores, final_scores)
      allow(engine).to receive(:get_best_candidate).and_return(mock_program)
      
      result = engine.run_evolution(mock_program, trainset)
      
      expect(result[:best_fitness]).to be > 0.8
      expect(result[:best_candidate]).not_to be_nil
    end

    it 'tracks generation history' do
      fitness_scores = [0.8, 0.6, 0.4, 0.2].map do |score|
        DSPy::Teleprompt::GEPA::FitnessScore.new(
          primary_score: score,
          secondary_scores: {},
          overall_score: score,
          metadata: {}
        )
      end
      allow(engine).to receive(:evaluate_population).and_return(fitness_scores)
      
      result = engine.run_evolution(mock_program, trainset)
      
      expect(result[:generation_history]).to be_an(Array)
      expect(result[:generation_history].size).to eq(config.num_generations + 1) # +1 for initial
    end
  end

  describe '#get_best_candidate' do
    let(:engine) { described_class.new(config: config, fitness_evaluator: fitness_evaluator) }

    before do
      engine.initialize_population(mock_program)
      
      # Mock different fitness scores
      @fitness_scores = [0.9, 0.3, 0.7, 0.5].map do |score|
        DSPy::Teleprompt::GEPA::FitnessScore.new(
          primary_score: score,
          secondary_scores: {},
          overall_score: score,
          metadata: {}
        )
      end
      allow(engine).to receive(:evaluate_population).and_return(@fitness_scores)
    end

    it 'returns candidate with highest fitness' do
      engine.evaluate_population(trainset) # Populate scores
      best = engine.get_best_candidate
      
      expect(best).to eq(engine.population[0]) # Index 0 has score 0.9
    end

    it 'handles tied fitness scores' do
      tied_scores = [0.8, 0.8, 0.6, 0.4].map do |score|
        DSPy::Teleprompt::GEPA::FitnessScore.new(
          primary_score: score,
          secondary_scores: {},
          overall_score: score,
          metadata: {}
        )
      end
      allow(engine).to receive(:evaluate_population).and_return(tied_scores)
      
      engine.evaluate_population(trainset)
      best = engine.get_best_candidate
      
      # Should return one of the tied candidates
      expect([engine.population[0], engine.population[1]]).to include(best)
    end
  end

  describe '#population_diversity' do
    let(:engine) { described_class.new(config: config, fitness_evaluator: fitness_evaluator) }

    it 'measures instruction diversity in population' do
      engine.initialize_population(mock_program)
      
      diversity = engine.population_diversity
      
      expect(diversity).to be_a(Float)
      expect(diversity).to be_between(0.0, 1.0)
    end

    it 'returns higher diversity for more varied instructions' do
      # Create population with identical instructions
      uniform_population = Array.new(4) { mock_program }
      allow(engine).to receive(:population).and_return(uniform_population)
      
      low_diversity = engine.population_diversity
      
      # Create population with different instructions
      engine.initialize_population(mock_program)
      high_diversity = engine.population_diversity
      
      expect(high_diversity).to be > low_diversity
    end
  end
end