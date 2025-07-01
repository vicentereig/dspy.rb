# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Evaluation Integration with Real LM', :vcr do
  let(:openai_lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY']) }

  # Test signature for math evaluation (without reasoning field since ChainOfThought will add it)
  class MathEvaluation < DSPy::Signature
    description "Solve basic arithmetic problems."

    input do
      const :problem, String, description: "An arithmetic problem"
    end

    output do
      const :answer, String, description: "The numerical answer"
    end
  end

  before do
    DSPy.configure do |config|
      config.lm = openai_lm
    end
  end

  describe 'real LM evaluation' do
    it 'evaluates math problems with chain of thought', vcr: { cassette_name: 'evaluation/math_chain_of_thought' } do
      # Create examples using DSPy::Example for type safety
      examples = [
        DSPy::Example.new(
          signature_class: MathEvaluation,
          input: { problem: "What is 15 + 27?" },
          expected: { answer: "42" }
        ),
        DSPy::Example.new(
          signature_class: MathEvaluation,
          input: { problem: "What is 8 × 7?" },
          expected: { answer: "56" }
        )
      ]

      # Create program and evaluator
      math_program = DSPy::ChainOfThought.new(MathEvaluation)
      
      # Custom metric that checks if the answer is correct
      answer_metric = proc do |example, prediction|
        expected_answer = example.expected_values[:answer]
        actual_answer = prediction[:answer]
        expected_answer == actual_answer
      end

      evaluator = DSPy::Evaluate.new(math_program, metric: answer_metric)

      # Run evaluation
      result = evaluator.evaluate(examples, display_progress: false)

      # Verify results
      expect(result).to be_a(DSPy::Evaluate::BatchEvaluationResult)
      expect(result.total_examples).to eq(2)
      expect(result.pass_rate).to be_between(0.0, 1.0)
      
      # Check individual results
      expect(result.results).to all(be_a(DSPy::Evaluate::EvaluationResult))
      result.results.each do |individual|
        expect(individual.prediction).to respond_to(:answer)
        expect(individual.prediction).to respond_to(:reasoning)
      end
    end

    it 'handles evaluation errors gracefully', vcr: { cassette_name: 'evaluation/error_handling' } do
      # Example that might cause issues
      problematic_example = DSPy::Example.new(
        signature_class: MathEvaluation,
        input: { problem: "What is the square root of -1 in real numbers?" },
        expected: { answer: "undefined" }
      )

      math_program = DSPy::ChainOfThought.new(MathEvaluation)
      
      # Metric that's more flexible
      flexible_metric = proc do |example, prediction|
        # Just check that we got some response
        prediction && prediction.respond_to?(:answer) && !prediction.answer.to_s.empty?
      end

      evaluator = DSPy::Evaluate.new(
        math_program, 
        metric: flexible_metric,
        max_errors: 1  # Allow some errors
      )

      # This should not raise an exception
      expect {
        result = evaluator.evaluate([problematic_example], display_progress: false)
        expect(result).to be_a(DSPy::Evaluate::BatchEvaluationResult)
      }.not_to raise_error
    end

    it 'works with single example evaluation', vcr: { cassette_name: 'evaluation/single_example' } do
      example = DSPy::Example.new(
        signature_class: MathEvaluation,
        input: { problem: "What is 12 + 8?" },
        expected: { answer: "20" }
      )

      math_program = DSPy::ChainOfThought.new(MathEvaluation)
      
      # Simple exact match metric for answer
      exact_match = proc do |example, prediction|
        example.expected_values[:answer] == prediction[:answer]
      end

      evaluator = DSPy::Evaluate.new(math_program, metric: exact_match)

      # Evaluate single example
      result = evaluator.call(example)

      expect(result).to be_a(DSPy::Evaluate::EvaluationResult)
      expect(result.example).to eq(example)
      expect(result.prediction).to respond_to(:answer)
      expect(result.prediction).to respond_to(:reasoning)
      expect([true, false]).to include(result.passed)  # Could pass or fail, just shouldn't error
    end
  end

  describe 'evaluation with different metrics' do
    let(:example) do
      DSPy::Example.new(
        signature_class: MathEvaluation,
        input: { problem: "What is 6 × 9?" },
        expected: { answer: "54" }
      )
    end

    let(:math_program) { DSPy::ChainOfThought.new(MathEvaluation) }

    it 'works with contains metric', vcr: { cassette_name: 'evaluation/contains_metric' } do
      # Check if reasoning contains key mathematical concept
      contains_metric = proc do |example, prediction|
        prediction[:reasoning]&.downcase&.include?('multiply') || 
        prediction[:reasoning]&.include?('×') ||
        prediction[:reasoning]&.include?('*')
      end

      evaluator = DSPy::Evaluate.new(math_program, metric: contains_metric)
      result = evaluator.call(example)

      expect(result).to be_a(DSPy::Evaluate::EvaluationResult)
      expect([true, false]).to include(result.passed)
    end

    it 'works with composite metrics', vcr: { cassette_name: 'evaluation/composite_metric' } do
      # Check both answer correctness and reasoning quality
      composite_metric = proc do |example, prediction|
        answer_correct = example.expected_values[:answer] == prediction[:answer]
        has_reasoning = prediction[:reasoning]&.length.to_i > 10
        
        answer_correct && has_reasoning
      end

      evaluator = DSPy::Evaluate.new(math_program, metric: composite_metric)
      result = evaluator.call(example)

      expect(result).to be_a(DSPy::Evaluate::EvaluationResult)
      expect(result.metrics).to include(:passed)
    end
  end
end