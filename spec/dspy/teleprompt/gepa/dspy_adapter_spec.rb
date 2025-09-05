# frozen_string_literal: true

require 'spec_helper'
require 'dspy/teleprompt/gepa'

RSpec.describe DSPy::Teleprompt::DspyAdapter do
  # Test signature for adapter testing
  class AdapterTestSignature < DSPy::Signature
    description "Test signature for DSPy adapter"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:test_student) { MockableTestModule.new(AdapterTestSignature) }
  let(:simple_metric) { proc { |example, prediction| example.expected_values[:answer] == prediction.answer ? 1.0 : 0.0 } }
  let(:feedback_metric) do
    proc do |example, prediction|
      expected = example.expected_values[:answer]
      actual = prediction.answer
      
      if expected == actual
        DSPy::Teleprompt::ScoreWithFeedback.new(
          score: 1.0,
          feedback: "Perfect match",
          prediction: prediction
        )
      else
        DSPy::Teleprompt::ScoreWithFeedback.new(
          score: 0.0,
          feedback: "Expected '#{expected}' but got '#{actual}'",
          prediction: prediction
        )
      end
    end
  end

  let(:example) do
    DSPy::Example.new(
      signature_class: AdapterTestSignature,
      input: { question: "What is 2+2?" },
      expected: { answer: "4" }
    )
  end

  describe 'initialization' do
    it 'creates adapter with required parameters' do
      adapter = described_class.new(
        student: test_student,
        metric: simple_metric
      )
      
      expect(adapter).to be_a(DSPy::Teleprompt::DspyAdapter)
    end

    it 'accepts optional feedback_map and custom_instruction_proposer' do
      feedback_map = { "question" => "test" }
      custom_proposer = proc { |instruction, dataset| "Improved: #{instruction}" }
      
      adapter = described_class.new(
        student: test_student,
        metric: simple_metric,
        feedback_map: feedback_map,
        custom_instruction_proposer: custom_proposer
      )
      
      expect(adapter).to be_a(DSPy::Teleprompt::DspyAdapter)
    end
  end

  describe '#build_program' do
    let(:adapter) { described_class.new(student: test_student, metric: simple_metric) }

    it 'returns a program-like object' do
      program = adapter.build_program("Solve this problem carefully")
      
      expect(program).not_to be_nil
      expect(program).to respond_to(:call).or respond_to(:forward)
    end

    it 'handles programs without modifiable signature' do
      readonly_student = double('student')
      adapter = described_class.new(student: readonly_student, metric: simple_metric)
      
      program = adapter.build_program("Test instruction")
      
      expect(program).to eq(readonly_student)
    end
  end

  describe '#evaluate_batch' do
    let(:adapter) { described_class.new(student: test_student, metric: simple_metric) }
    let(:batch) { [example] }

    it 'evaluates batch with simple metric' do
      # Configure student to return expected answer
      test_student.mock_response = { answer: "4" }
      
      results = adapter.evaluate_batch(batch, "Answer the question")
      
      expect(results).to be_an(Array)
      expect(results.size).to eq(1)
      expect(results.first).to eq(1.0)
    end

    it 'evaluates batch with feedback metric' do
      adapter = described_class.new(student: test_student, metric: feedback_metric)
      test_student.mock_response = { answer: "4" }
      
      results = adapter.evaluate_batch(batch, "Answer the question")
      
      expect(results).to be_an(Array)
      expect(results.size).to eq(1)
      expect(results.first).to be_a(DSPy::Teleprompt::ScoreWithFeedback)
      expect(results.first.score).to eq(1.0)
      expect(results.first.feedback).to eq("Perfect match")
    end

    it 'handles evaluation errors gracefully' do
      # Configure student to raise error
      allow(test_student).to receive(:call).and_raise(StandardError, "Test error")
      
      results = adapter.evaluate_batch(batch, "Test instruction")
      
      expect(results).to eq([0.0])
    end

    it 'can disable trace capture' do
      test_student.mock_response = { answer: "4" }
      
      results = adapter.evaluate_batch(batch, "Answer the question", capture_traces: false)
      
      expect(results.first).to eq(1.0)
    end
  end

  describe '#make_reflective_dataset' do
    let(:adapter) { described_class.new(student: test_student, metric: feedback_metric) }
    
    let(:examples) { [example] }
    let(:predictions) do
      [DSPy::Prediction.new(signature_class: AdapterTestSignature, answer: "wrong")]
    end
    let(:scores) do
      [DSPy::Teleprompt::ScoreWithFeedback.new(
        score: 0.2,
        feedback: "Incorrect answer provided",
        prediction: predictions.first
      )]
    end

    it 'creates reflective dataset from failed predictions' do
      dataset = adapter.make_reflective_dataset(examples, predictions, scores, threshold: 0.5)
      
      expect(dataset).to be_an(Array)
      expect(dataset.size).to eq(1)
      
      reflection = dataset.first
      expect(reflection['input']).to eq({ question: "What is 2+2?" })
      expect(reflection['expected']).to eq({ answer: "4" })
      expect(reflection['score']).to eq(0.2)
      expect(reflection['feedback']).to eq("Incorrect answer provided")
    end

    it 'filters out successful predictions above threshold' do
      good_scores = [DSPy::Teleprompt::ScoreWithFeedback.new(score: 0.8, feedback: "Good")]
      
      dataset = adapter.make_reflective_dataset(examples, predictions, good_scores, threshold: 0.5)
      
      expect(dataset).to be_empty
    end

    it 'handles simple float scores' do
      simple_scores = [0.3]
      
      dataset = adapter.make_reflective_dataset(examples, predictions, simple_scores)
      
      expect(dataset.size).to eq(1)
      expect(dataset.first['feedback']).to include("Low performance (score: 0.3)")
    end
  end

  describe '#propose_new_texts' do
    let(:adapter) { described_class.new(student: test_student, metric: simple_metric) }
    let(:reflective_dataset) do
      [{
        'input' => { question: "What is 2+2?" },
        'feedback' => "Answer was unclear and incomplete"
      }]
    end

    it 'uses custom proposer when provided' do
      custom_proposer = proc do |instruction, dataset|
        "Custom improvement for: #{instruction}"
      end
      
      adapter = described_class.new(
        student: test_student,
        metric: simple_metric,
        custom_instruction_proposer: custom_proposer
      )
      
      proposals = adapter.propose_new_texts("Original instruction", reflective_dataset)
      
      expect(proposals).to include("Custom improvement for: Original instruction")
    end

    it 'uses built-in analysis when no custom proposer provided' do
      proposals = adapter.propose_new_texts("Solve this", reflective_dataset)
      
      expect(proposals).to be_an(Array)
      expect(proposals).not_to be_empty
      expect(proposals.first).to be_a(String)
    end

    it 'provides specific improvements based on feedback patterns' do
      unclear_dataset = [{
        'feedback' => "The answer was unclear and ambiguous"
      }]
      
      proposals = adapter.propose_new_texts("Answer this", unclear_dataset)
      
      expect(proposals.any? { |p| p.include?('clear') }).to be(true)
    end

    it 'handles empty reflective dataset' do
      proposals = adapter.propose_new_texts("Test instruction", [])
      
      expect(proposals).to eq(["Test instruction"])
    end
  end

  describe 'integration with GEPAFeedbackMetric protocol' do
    # Custom metric implementing GEPAFeedbackMetric
    class TestFeedbackMetric
      include DSPy::Teleprompt::GEPAFeedbackMetric

      def call(example, prediction, trace = nil)
        expected = example.expected_values[:answer]
        actual = prediction.answer

        if expected == actual
          DSPy::Teleprompt::ScoreWithFeedback.new(
            score: 1.0,
            feedback: "Correct answer provided"
          )
        else
          DSPy::Teleprompt::ScoreWithFeedback.new(
            score: 0.0,
            feedback: "Expected #{expected}, got #{actual}. Consider the mathematical operation more carefully."
          )
        end
      end
    end

    let(:feedback_metric_instance) { TestFeedbackMetric.new }
    let(:adapter) { described_class.new(student: test_student, metric: feedback_metric_instance) }

    it 'works with GEPAFeedbackMetric implementation' do
      test_student.mock_response = { answer: "5" }
      batch = [example]
      
      results = adapter.evaluate_batch(batch, "Calculate carefully")
      
      expect(results.first).to be_a(DSPy::Teleprompt::ScoreWithFeedback)
      expect(results.first.score).to eq(0.0)
      expect(results.first.feedback).to include("Consider the mathematical operation more carefully")
    end
  end
end