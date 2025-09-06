# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GEPA Complete Optimization Integration', vcr: { cassette_name: 'gepa_complete_optimization' } do
  # Test signature for complex optimization
  class CompleteOptimizationSignature < DSPy::Signature
    description "Solve complex reasoning problems with step-by-step analysis"

    input do
      const :problem, String, description: "A complex reasoning problem to solve"
    end

    output do
      const :answer, String, description: "The final answer"
      const :reasoning, String, description: "Step-by-step reasoning process"
      const :confidence, Float, description: "Confidence level (0-1)"
    end
  end

  # Test program for complete optimization
  class CompleteOptimizationProgram
    attr_accessor :signature_class

    def initialize
      @signature_class = CompleteOptimizationSignature
      @predict = DSPy::Predict.new(CompleteOptimizationSignature)
    end

    def call(problem:)
      prediction = @predict.call(problem: problem)

      # Extract confidence from reasoning or default to 0.7
      confidence = extract_confidence(prediction.reasoning) || 0.7

      DSPy::Prediction.new(
        signature_class: CompleteOptimizationSignature,
        answer: prediction.answer || "Unable to solve",
        reasoning: prediction.reasoning || "No reasoning provided",
        confidence: confidence
      )
    end

    private

    def extract_confidence(reasoning)
      return 0.7 unless reasoning

      # Simple confidence extraction based on reasoning quality
      if reasoning.length > 100 && reasoning.include?("because")
        0.8
      elsif reasoning.length > 50
        0.6
      else
        0.4
      end
    end
  end

  let(:program) { CompleteOptimizationProgram.new }

  # Complex training set for genetic optimization
  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: CompleteOptimizationSignature,
        input: { problem: "If a train travels 120 miles in 2 hours, what is its speed in mph?" },
        expected: {
          answer: "60 mph",
          reasoning: "Speed = Distance / Time = 120 miles / 2 hours = 60 mph",
          confidence: 0.9
        }
      ),
      DSPy::Example.new(
        signature_class: CompleteOptimizationSignature,
        input: { problem: "What is 15% of 200?" },
        expected: {
          answer: "30",
          reasoning: "15% of 200 = 0.15 × 200 = 30",
          confidence: 0.8
        }
      ),
      DSPy::Example.new(
        signature_class: CompleteOptimizationSignature,
        input: { problem: "If it takes 3 painters 4 hours to paint a wall, how long would it take 6 painters?" },
        expected: {
          answer: "2 hours",
          reasoning: "This is inverse proportion. 3 painters × 4 hours = 12 painter-hours needed. 12 painter-hours ÷ 6 painters = 2 hours",
          confidence: 0.7
        }
      ),
      DSPy::Example.new(
        signature_class: CompleteOptimizationSignature,
        input: { problem: "What comes next in the sequence: 2, 6, 18, 54, ?" },
        expected: {
          answer: "162",
          reasoning: "Each number is multiplied by 3: 2×3=6, 6×3=18, 18×3=54, so 54×3=162",
          confidence: 0.8
        }
      )
    ]
  end

  let(:valset) do
    [
      DSPy::Example.new(
        signature_class: CompleteOptimizationSignature,
        input: { problem: "If a recipe calls for 3 cups of flour for 12 cookies, how much flour is needed for 20 cookies?" },
        expected: {
          answer: "5 cups",
          reasoning: "Ratio is 3 cups : 12 cookies = 1 cup : 4 cookies. For 20 cookies: 20 ÷ 4 = 5 cups",
          confidence: 0.8
        }
      )
    ]
  end

  # Multi-dimensional accuracy metric
  let(:comprehensive_metric) do
    proc do |example, prediction|
      expected_answer = example.expected_values[:answer].downcase.strip
      actual_answer = prediction.answer.to_s.downcase.strip

      # Answer accuracy (primary)
      answer_score = expected_answer == actual_answer ? 1.0 : 0.0

      # Reasoning quality (secondary)
      reasoning_score = calculate_reasoning_quality(prediction.reasoning, example.expected_values[:reasoning])

      # Confidence calibration (secondary)
      confidence_score = calculate_confidence_calibration(prediction.confidence, answer_score)

      # Combined score weighted toward answer accuracy
      (answer_score * 0.6) + (reasoning_score * 0.25) + (confidence_score * 0.15)
    end
  end

  describe 'Complete GEPA genetic algorithm optimization' do
    it 'performs full genetic optimization with all components' do
      # Create GEPA with full genetic algorithm enabled
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
      config.num_generations = 2   # Reduced for testing
      config.population_size = 2   # Reduced for testing
      config.mutation_rate = 0.8   # High mutation for exploration
      config.crossover_rate = 0.6  # Moderate crossover
      config.use_pareto_selection = true

      gepa = DSPy::Teleprompt::GEPA.new(metric: comprehensive_metric, config: config)

      # Measure initial performance
      initial_scores = []
      trainset.each do |example|
        prediction = program.call(**example.input_values)
        score = comprehensive_metric.call(example, prediction)
        initial_scores << score
      end
      initial_avg = initial_scores.sum / initial_scores.size

      # Run complete optimization
      result = gepa.compile(program, trainset: trainset, valset: valset)

      # Verify result structure
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).not_to be_nil
      expect(result.best_score_value).to be_a(Float)

      # Verify comprehensive result metadata
      expect(result.metadata[:implementation_status]).to eq('Phase 2 - Complete Implementation')
      expect(result.metadata[:optimizer]).to eq('GEPA')
      expect(result.metadata[:optimization_run_id]).to match(/^gepa-run-[a-f0-9]{8}$/)

      # Verify reflection insights are included
      reflection_insights = result.metadata[:reflection_insights]
      expect(reflection_insights).to be_a(Hash)
      expect(reflection_insights[:diagnosis]).to be_a(String)
      expect(reflection_insights[:improvements]).to be_an(Array)
      expect(reflection_insights[:confidence]).to be_between(0.0, 1.0)
      expect(reflection_insights[:suggested_mutations]).to be_an(Array)

      # Verify trace analysis
      trace_analysis = result.metadata[:trace_analysis]
      expect(trace_analysis).to be_a(Hash)
      expect(trace_analysis[:total_traces]).to be >= 0
      expect(trace_analysis[:execution_timespan]).to be >= 0.0

      # Verify component versions
      component_versions = result.metadata[:component_versions]
      expect(component_versions).to be_a(Hash)
      expect(component_versions[:genetic_engine]).to eq('v2.0')
      expect(component_versions[:fitness_evaluator]).to eq('v2.0')
      expect(component_versions[:reflection_engine]).to eq('v2.0')
      expect(component_versions[:mutation_engine]).to eq('v2.0')
      expect(component_versions[:crossover_engine]).to eq('v2.0')
      expect(component_versions[:pareto_selector]).to eq('v2.0')

      # Verify optimization history
      history = result.history
      expect(history[:phase]).to eq('Phase 2 - Complete GEPA')
      expect(history[:num_generations]).to be >= 0
      expect(history[:population_size]).to eq(config.population_size)
      expect(history[:generation_history]).to be_an(Array)
      expect(history[:mutation_rate]).to eq(config.mutation_rate)
      expect(history[:crossover_rate]).to eq(config.crossover_rate)
      expect(history[:selection_strategy]).to eq('pareto')

      # Verify comprehensive scores
      scores = result.scores
      expect(scores[:fitness_score]).to be_a(Float)
      expect(scores[:validation_score]).to be_a(Float)
      expect(scores[:primary_score]).to be_a(Float)
      expect(scores).to include(:token_efficiency, :consistency, :latency)

      # Test optimized program performance
      optimized_program = result.optimized_program
      final_scores = []
      trainset.each do |example|
        prediction = optimized_program.call(**example.input_values)
        score = comprehensive_metric.call(example, prediction)
        final_scores << score
      end
      final_avg = final_scores.sum / final_scores.size

      # Log performance metrics for analysis
      puts "GEPA Complete Optimization Results:"
      puts "Initial average score: #{initial_avg.round(3)}"
      puts "Final average score: #{final_avg.round(3)}"
      puts "Improvement: #{(final_avg - initial_avg).round(3)}"
      puts "Reflection confidence: #{reflection_insights[:confidence].round(3)}"
      puts "Total traces collected: #{trace_analysis[:total_traces]}"
      puts "Optimization timespan: #{trace_analysis[:execution_timespan].round(2)}s"
      puts "Generations completed: #{history[:num_generations]}"

      # Performance should be maintained or improved
      expect(final_avg).to be >= initial_avg * 0.8  # Allow for some variance
    end
  end

  describe 'GEPA error handling and recovery' do
    it 'handles optimization failures gracefully' do
      # Create GEPA with invalid configuration to trigger error
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
      config.num_generations = -1  # Invalid value to trigger error

      gepa = DSPy::Teleprompt::GEPA.new(metric: comprehensive_metric, config: config)

      # Should not raise error, but return fallback result
      result = gepa.compile(program, trainset: trainset, valset: valset)

      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.metadata[:implementation_status]).to eq('Phase 2 - Error Recovery')
      expect(result.history[:phase]).to eq('Phase 2 - Error Recovery')
      expect(result.history[:error]).to be_a(String)
      expect(result.metadata[:error_details]).to be_a(Hash)
      expect(result.metadata[:error_details][:recovery_strategy]).to eq('fallback_to_original')

      # Original program should be returned
      expect(result.optimized_program).to eq(program)
    end
  end

  describe 'Component integration validation' do
    it 'validates all GEPA components work together' do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
      config.num_generations = 2
      config.population_size = 3

      gepa = DSPy::Teleprompt::GEPA.new(metric: comprehensive_metric, config: config)

      # Test component creation methods directly
      fitness_evaluator = gepa.send(:create_fitness_evaluator)
      genetic_engine = gepa.send(:create_genetic_engine, fitness_evaluator)
      reflection_engine = gepa.send(:create_reflection_engine)
      mutation_engine = gepa.send(:create_mutation_engine)
      crossover_engine = gepa.send(:create_crossover_engine)
      pareto_selector = gepa.send(:create_pareto_selector, fitness_evaluator)

      expect(fitness_evaluator).to be_a(DSPy::Teleprompt::GEPA::FitnessEvaluator)
      expect(genetic_engine).to be_a(DSPy::Teleprompt::GEPA::GeneticEngine)
      expect(reflection_engine).to be_a(DSPy::Teleprompt::GEPA::ReflectionEngine)
      expect(mutation_engine).to be_a(DSPy::Teleprompt::GEPA::MutationEngine)
      expect(crossover_engine).to be_a(DSPy::Teleprompt::GEPA::CrossoverEngine)
      expect(pareto_selector).to be_a(DSPy::Teleprompt::GEPA::ParetoSelector)

      # Run minimal optimization to verify integration
      result = gepa.compile(program, trainset: trainset.take(2), valset: valset.take(1))

      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.metadata[:implementation_status]).to eq('Phase 2 - Complete Implementation')
    end
  end

  private

  def calculate_reasoning_quality(actual_reasoning, expected_reasoning)
    return 0.0 unless actual_reasoning && expected_reasoning

    actual_words = actual_reasoning.downcase.split
    expected_words = expected_reasoning.downcase.split

    # Simple overlap score
    overlap = (actual_words & expected_words).size.to_f
    union = (actual_words | expected_words).size.to_f

    union > 0 ? overlap / union : 0.0
  end

  def calculate_confidence_calibration(predicted_confidence, actual_accuracy)
    return 0.5 unless predicted_confidence

    # Reward well-calibrated confidence (high confidence + correct, low confidence + incorrect)
    if actual_accuracy > 0.5
      predicted_confidence  # Reward high confidence when correct
    else
      1.0 - predicted_confidence  # Reward low confidence when incorrect
    end
  end
end
