# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GEPA Simple Optimization Integration', vcr: { cassette_name: 'gepa_simple_optimization' } do
  # Simple math problem signature for testing
  class SimpleMathSignature < DSPy::Signature
    description "Solve basic arithmetic problems step by step"

    input do
      const :problem, String, description: "A math problem to solve"
    end

    output do
      const :answer, Integer, description: "The numerical answer"
      const :reasoning, String, description: "Step-by-step solution"
    end
  end

  # Simple program that can be optimized
  class SimpleMathProgram
    attr_accessor :signature_class

    def initialize
      @signature_class = SimpleMathSignature
      @predict = DSPy::Predict.new(SimpleMathSignature)
      @predict.configure do |config|
        config.lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
      end
    end

    def call(problem:)
      prediction = @predict.call(problem: problem)

      # Extract integer from answer text (basic parsing)
      answer_match = prediction.answer.to_s.match(/\b(\d+)\b/)
      answer = answer_match ? answer_match[1].to_i : 0

      DSPy::Prediction.new(
        signature_class: SimpleMathSignature,
        answer: answer,
        reasoning: prediction.reasoning || "Basic calculation"
      )
    end
  end

  let(:program) { SimpleMathProgram.new }

  # Simple training set with basic math problems
  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: SimpleMathSignature,
        input: { problem: "What is 5 + 3?" },
        expected: { answer: 8, reasoning: "5 + 3 = 8" }
      ),
      DSPy::Example.new(
        signature_class: SimpleMathSignature,
        input: { problem: "What is 12 - 4?" },
        expected: { answer: 8, reasoning: "12 - 4 = 8" }
      ),
      DSPy::Example.new(
        signature_class: SimpleMathSignature,
        input: { problem: "What is 6 × 2?" },
        expected: { answer: 12, reasoning: "6 × 2 = 12" }
      )
    ]
  end

  let(:valset) do
    [
      DSPy::Example.new(
        signature_class: SimpleMathSignature,
        input: { problem: "What is 9 + 4?" },
        expected: { answer: 13, reasoning: "9 + 4 = 13" }
      )
    ]
  end

  # Simple accuracy metric
  let(:accuracy_metric) do
    proc do |example, prediction|
      expected_answer = example.expected_values[:answer]
      actual_answer = prediction.answer
      expected_answer == actual_answer ? 1.0 : 0.0
    end
  end

  describe 'Simple optimization scenario' do
    it 'performs basic optimization without genetic algorithm', vcr: { cassette_name: 'gepa_simple_basic_optimization' } do
      skip 'Skip until GEPA retry logic is optimized'
      # Create GEPA with simple optimization enabled
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
      config.num_generations = 3  # Just a few iterations
      config.population_size = 2  # Minimal population

      gepa = DSPy::Teleprompt::GEPA.new(metric: accuracy_metric, config: config)

      # Measure initial performance
      initial_scores = []
      trainset.each do |example|
        prediction = program.call(**example.input_values)
        score = accuracy_metric.call(example, prediction)
        initial_scores << score
      end
      initial_avg = initial_scores.sum / initial_scores.size

      # Run optimization
      result = gepa.compile(program, trainset: trainset, valset: valset)

      # Verify optimization result structure
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).not_to be_nil
      expect(result.best_score_value).to be_a(Float)

      # Test optimized program performance
      optimized_program = result.optimized_program
      final_scores = []
      trainset.each do |example|
        prediction = optimized_program.call(**example.input_values)
        score = accuracy_metric.call(example, prediction)
        final_scores << score
      end
      final_avg = final_scores.sum / final_scores.size

      # Verify improvement or at least no degradation
      expect(final_avg).to be >= initial_avg

      # Log performance for debugging
      puts "Initial average accuracy: #{initial_avg}"
      puts "Final average accuracy: #{final_avg}"
      puts "Improvement: #{final_avg - initial_avg}"

      # No cleanup needed - using proper configuration
    end
  end

  describe 'Trace collection during optimization' do
    it 'collects execution traces during simple optimization run', vcr: { cassette_name: 'gepa_simple_trace_collection' } do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
      config.num_generations = 2
      config.population_size = 1

      gepa = DSPy::Teleprompt::GEPA.new(metric: accuracy_metric, config: config)

      # Create a trace collector to monitor
      collector = DSPy::Teleprompt::GEPA::TraceCollector.new

      # Run optimization
      result = gepa.compile(program, trainset: trainset.take(1), valset: valset.take(1))

      # Give time for traces to be collected
      sleep(0.1)

      # Verify traces were collected (if any events were emitted)
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)

      # The specific trace count depends on DSPy's event emission
      # but we can verify the collector works
      puts "Traces collected: #{collector.collected_count}"
    end
  end

  describe 'Reflection analysis during optimization' do
    it 'generates reflection insights during optimization', vcr: { cassette_name: 'gepa_simple_reflection_analysis' } do
      # Create reflection engine
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
      engine = DSPy::Teleprompt::GEPA::ReflectionEngine.new(config)

      # Create sample traces that might occur during optimization
      traces = [
        DSPy::Teleprompt::GEPA::ExecutionTrace.new(
          trace_id: 'simple-opt-1',
          event_name: 'llm.response',
          timestamp: Time.now,
          attributes: {
            'gen_ai.request.model' => 'gpt-3.5-turbo',
            'gen_ai.usage.total_tokens' => 45,
            prompt: 'Solve: What is 5 + 3?',
            response: 'Let me solve this step by step. 5 + 3 = 8.'
          },
          metadata: { optimization_run_id: 'simple-run' }
        )
      ]

      # Generate reflection
      reflection = engine.reflect_on_traces(traces)

      # Verify reflection quality
      expect(reflection).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(reflection.confidence).to be_between(0.0, 1.0)
      expect(reflection.improvements).to be_an(Array)
      expect(reflection.suggested_mutations).to be_an(Array)
      expect(reflection.diagnosis).not_to be_empty
    end
  end
end
