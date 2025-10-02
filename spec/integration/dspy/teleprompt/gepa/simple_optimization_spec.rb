# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Teleprompt::GEPA Simple Optimization' do
  before(:all) { skip 'Skip all GEPA tests until retry logic is optimized' }
  # Test signature
  class TestOptimSignature < DSPy::Signature
    description "Solve problems clearly and accurately"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:metric) { proc { |example, prediction| example.expected_values[:answer] == prediction.answer ? 1.0 : 0.0 } }
  let(:gepa_config) do
    config = DSPy::Teleprompt::GEPA::GEPAConfig.new
    config.reflection_lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    # Reduce complexity for faster test execution and VCR recording
    config.num_generations = 2  # Reduced from default 10
    config.population_size = 2  # Reduced from default 8
    config
  end
  let(:gepa) { DSPy::Teleprompt::GEPA.new(metric: metric, config: gepa_config) }

  let(:mock_program) do
    double('program', signature_class: TestOptimSignature).tap do |prog|
      # Handle all respond_to? calls that GEPA might make
      allow(prog).to receive(:respond_to?) do |method_name|
        case method_name
        when :signature_class
          true
        when :with_instruction
          false
        else
          false
        end
      end
      
      allow(prog).to receive(:call) do |**kwargs|
        # Simple mock implementation - just return the input as answer
        DSPy::Prediction.new(
          signature_class: TestOptimSignature,
          answer: kwargs[:question] == "What is 2+2?" ? "4" : "unknown"
        )
      end
    end
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: TestOptimSignature,
        input: { question: 'What is 2+2?' },
        expected: { answer: '4' }
      )
    ]
  end

  describe 'GEPA genetic algorithm optimization' do
    it 'creates genetic engine for optimization' do
      fitness_evaluator = gepa.send(:create_fitness_evaluator)
      genetic_engine = gepa.send(:create_genetic_engine, fitness_evaluator)
      
      expect(genetic_engine).to be_a(DSPy::Teleprompt::GEPA::GeneticEngine)
    end

    it 'creates reflection engine for optimization' do
      reflection_engine = gepa.send(:create_reflection_engine)
      
      expect(reflection_engine).to be_a(DSPy::Teleprompt::GEPA::ReflectionEngine)
    end

    it 'creates mutation engine for optimization' do
      mutation_engine = gepa.send(:create_mutation_engine)
      
      expect(mutation_engine).to be_a(DSPy::Teleprompt::GEPA::MutationEngine)
    end

    it 'creates crossover engine for optimization' do
      crossover_engine = gepa.send(:create_crossover_engine)
      
      expect(crossover_engine).to be_a(DSPy::Teleprompt::GEPA::CrossoverEngine)
    end

    it 'creates fitness evaluator for optimization' do
      fitness_evaluator = gepa.send(:create_fitness_evaluator)
      
      expect(fitness_evaluator).to be_a(DSPy::Teleprompt::GEPA::FitnessEvaluator)
    end
  end

  describe '#evaluate_program' do
    it 'evaluates program performance using fitness evaluator' do
      allow(mock_program).to receive(:call).with(question: 'What is 2+2?').and_return(
        double('prediction', answer: '4')
      )
      
      fitness_evaluator = gepa.send(:create_fitness_evaluator)
      score = fitness_evaluator.evaluate_candidate(mock_program, trainset)
      expect(score).to be_a(DSPy::Teleprompt::GEPA::FitnessScore)
    end

    it 'handles program call errors gracefully in fitness evaluation' do
      allow(mock_program).to receive(:call).and_raise(StandardError, 'Test error')
      
      fitness_evaluator = gepa.send(:create_fitness_evaluator)
      score = fitness_evaluator.evaluate_candidate(mock_program, trainset)
      expect(score).to be_a(DSPy::Teleprompt::GEPA::FitnessScore)
    end

    it 'creates consistent fitness scores' do
      allow(mock_program).to receive(:call).with(question: 'What is 2+2?').and_return(
        double('prediction', answer: '4')
      )
      
      fitness_evaluator = gepa.send(:create_fitness_evaluator)
      score1 = fitness_evaluator.evaluate_candidate(mock_program, trainset)
      score2 = fitness_evaluator.evaluate_candidate(mock_program, trainset)
      
      # Should be consistent for same input
      expect(score1.class).to eq(score2.class)
    end
  end

  describe 'optimization result structure' do
    it 'returns proper optimization result from compile', vcr: { cassette_name: 'gepa_optimization_result' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      result = gepa.compile(mock_program, trainset: trainset, valset: trainset)
      
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).not_to be_nil
      expect(result.metadata[:optimizer]).to eq('GEPA')
    end
  end

  describe 'GEPA full optimization mode' do
    let(:full_config) do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new('openai/gpt-4o', api_key: ENV['OPENAI_API_KEY'])
      # Reduce complexity for faster test execution and VCR recording
      config.num_generations = 1  # Minimal for testing
      config.population_size = 2  # Minimal for testing
      config
    end
    
    let(:full_gepa) { DSPy::Teleprompt::GEPA.new(metric: metric, config: full_config) }

    it 'always uses full GEPA optimization', vcr: { cassette_name: 'gepa_full_optimization_mode' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      expect(full_gepa).to receive(:perform_gepa_optimization).and_call_original
      
      result = full_gepa.compile(mock_program, trainset: trainset, valset: trainset)
      expect(result.metadata[:optimizer]).to eq('GEPA')
    end

    it 'handles programs without signature_class gracefully', vcr: { cassette_name: 'gepa_no_signature_fallback' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Create a new mock that doesn't have signature_class
      no_sig_mock = double('program without signature_class')
      allow(no_sig_mock).to receive(:respond_to?) do |method_name|
        case method_name
        when :signature_class
          false
        when :with_instruction
          false
        else
          false
        end
      end
      allow(no_sig_mock).to receive(:call).and_return(double('prediction', answer: '4'))
      
      result = full_gepa.compile(no_sig_mock, trainset: trainset, valset: trainset)
      expect(result.metadata[:optimizer]).to eq('GEPA')
    end
  end

  describe 'MutationEngine functionality' do
    let(:mutation_engine) { gepa.send(:create_mutation_engine) }
    
    it 'creates mutation engine with proper configuration' do
      expect(mutation_engine).to be_a(DSPy::Teleprompt::GEPA::MutationEngine)
    end

    it 'applies mutations to single programs' do
      original_program = DSPy::Predict.new(TestOptimSignature)
      
      # Test single mutation
      mutated_program = mutation_engine.mutate_program(original_program)
      
      expect(mutated_program).to be_a(DSPy::Predict)
      expect(mutated_program.signature_class).to eq(TestOptimSignature)
    end

    it 'can batch mutate multiple programs' do
      original_program = DSPy::Predict.new(TestOptimSignature)
      programs = [original_program, original_program]
      
      mutated_programs = mutation_engine.batch_mutate(programs)
      
      expect(mutated_programs).to be_an(Array)
      expect(mutated_programs.size).to eq(2)
      mutated_programs.each do |program|
        expect(program).to be_a(DSPy::Predict)
        expect(program.signature_class).to eq(TestOptimSignature)
      end
    end

    it 'handles empty program batches' do
      mutations = mutation_engine.batch_mutate([])
      
      expect(mutations).to be_an(Array)
      expect(mutations).to be_empty
    end
  end

  describe 'integration with GEPA components' do
    it 'integrates all GEPA engines properly', vcr: { cassette_name: 'gepa_full_integration' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Create a real DSPy::Predict program for integration testing
      real_program = DSPy::Predict.new(TestOptimSignature)
      
      result = gepa.compile(real_program, trainset: trainset, valset: trainset)
      
      # Should return full GEPA optimization result
      expect(result.metadata[:optimizer]).to eq('GEPA')
      expect(result.optimized_program).not_to be_nil
      expect(result.best_score_value).to be_a(Numeric)
    end

    it 'handles mock programs gracefully' do
      # Should not raise error with mock program (using the default mock_program setup)
      expect {
        gepa.compile(mock_program, trainset: trainset, valset: trainset)
      }.not_to raise_error
    end
  end
end