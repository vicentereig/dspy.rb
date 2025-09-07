# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GEPA GeneticEngine' do
  before(:all) { skip 'Skip all GEPA tests until retry logic is optimized' }
  # Simple test signature for genetic engine testing
  class SimpleTestSignature < DSPy::Signature
    description "Simple test signature for genetic engine"

    input do
      const :input, String, description: "Test input"
    end

    output do
      const :output, String, description: "Test output"
    end
  end

  # Simple test program
  class SimpleTestProgram
    attr_accessor :signature_class

    def initialize(output_value = "test output")
      @signature_class = SimpleTestSignature
      @output_value = output_value
    end

    def call(input:)
      DSPy::Prediction.new(
        signature_class: SimpleTestSignature,
        output: @output_value
      )
    end
  end

  # Simple accuracy metric
  let(:metric) do
    proc do |example, prediction|
      expected = example.expected_values[:output]
      actual = prediction.output
      expected == actual ? 1.0 : 0.0
    end
  end

  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new.tap do |cfg|
      cfg.num_generations = 2
      cfg.population_size = 3
    end
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: SimpleTestSignature,
        input: { input: "test1" },
        expected: { output: "test output" }
      ),
      DSPy::Example.new(
        signature_class: SimpleTestSignature,
        input: { input: "test2" },
        expected: { output: "test output" }
      )
    ]
  end

  describe 'GeneticEngine integration with FitnessEvaluator' do
    it 'returns FitnessScore objects from run_evolution' do
      # Create fitness evaluator
      fitness_evaluator = DSPy::Teleprompt::GEPA::FitnessEvaluator.new(
        primary_metric: metric,
        config: config
      )

      # Create genetic engine - this should accept fitness_evaluator
      genetic_engine = DSPy::Teleprompt::GEPA::GeneticEngine.new(
        config: config,
        fitness_evaluator: fitness_evaluator
      )

      program = SimpleTestProgram.new

      # Run evolution
      result = genetic_engine.run_evolution(program, trainset)

      # The result should contain a FitnessScore object, not a Float
      expect(result).to have_key(:best_fitness)
      expect(result[:best_fitness]).to be_a(DSPy::Teleprompt::GEPA::FitnessScore)
      
      # FitnessScore should have the required methods
      expect(result[:best_fitness]).to respond_to(:overall_score)
      expect(result[:best_fitness]).to respond_to(:primary_score) 
      expect(result[:best_fitness]).to respond_to(:secondary_scores)
      
      # Values should be reasonable
      expect(result[:best_fitness].overall_score).to be_a(Float)
      expect(result[:best_fitness].primary_score).to be_a(Float)
      expect(result[:best_fitness].secondary_scores).to be_a(Hash)
    end

    it 'evaluates population using FitnessEvaluator' do
      fitness_evaluator = DSPy::Teleprompt::GEPA::FitnessEvaluator.new(
        primary_metric: metric,
        config: config
      )

      genetic_engine = DSPy::Teleprompt::GEPA::GeneticEngine.new(
        config: config,
        fitness_evaluator: fitness_evaluator
      )

      program = SimpleTestProgram.new

      # Initialize population
      genetic_engine.send(:initialize_population, program)

      # Evaluate population should return array of FitnessScore objects
      scores = genetic_engine.send(:evaluate_population, trainset)
      
      expect(scores).to be_an(Array)
      expect(scores).not_to be_empty
      scores.each do |score|
        expect(score).to be_a(DSPy::Teleprompt::GEPA::FitnessScore)
      end
    end
  end

  describe 'Current GeneticEngine behavior (failing tests)' do
    it 'now requires a proper FitnessEvaluator (type checking works)' do
      # The new constructor requires a proper FitnessEvaluator, not a mock
      expect {
        DSPy::Teleprompt::GEPA::GeneticEngine.new(
          config: config,
          fitness_evaluator: double('fitness_evaluator')
        )
      }.to raise_error(TypeError, /Expected type.*FitnessEvaluator/)
    end

    it 'old API no longer works (proving our fix)' do
      # The old API with 'metric' parameter should fail
      expect {
        DSPy::Teleprompt::GEPA::GeneticEngine.new(
          config: config,
          metric: metric
        )
      }.to raise_error(ArgumentError, /missing keyword.*fitness_evaluator/)
    end
  end
end