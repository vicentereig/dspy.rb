# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Evals Score Integration' do
  before do
    DSPy::Context.clear!
  end

  # Simple program for testing
  let(:simple_program) do
    Class.new do
      def call(question:)
        Struct.new(:answer).new("42")
      end
    end.new
  end

  # Simple metric
  let(:simple_metric) do
    ->(example, prediction) {
      expected = example.is_a?(Hash) ? example[:expected] || example[:answer] : example.answer
      { passed: prediction.answer == expected, score: prediction.answer == expected ? 1.0 : 0.0 }
    }
  end

  describe 'export_scores option' do
    it 'creates scores for each example when export_scores is true' do
      scores_created = []
      subscription_id = DSPy.events.subscribe('score.create') do |_name, attrs|
        scores_created << attrs
      end

      evaluator = DSPy::Evals.new(
        simple_program,
        metric: simple_metric,
        export_scores: true
      )

      examples = [
        { question: 'What is 6x7?', expected: '42' },
        { question: 'What is 2+2?', expected: '4' }
      ]

      evaluator.evaluate(examples, display_progress: false)

      # Should have created scores for each example (2)
      expect(scores_created.length).to be >= 2

      DSPy.events.unsubscribe(subscription_id)
    end

    it 'does not create scores when export_scores is false (default)' do
      scores_created = []
      subscription_id = DSPy.events.subscribe('score.create') do |_name, attrs|
        scores_created << attrs
      end

      evaluator = DSPy::Evals.new(
        simple_program,
        metric: simple_metric
        # export_scores defaults to false
      )

      examples = [{ question: 'What is 6x7?', expected: '42' }]
      evaluator.evaluate(examples, display_progress: false)

      expect(scores_created).to be_empty

      DSPy.events.unsubscribe(subscription_id)
    end

    it 'creates a batch score at the end of evaluation' do
      scores_created = []
      subscription_id = DSPy.events.subscribe('score.create') do |_name, attrs|
        scores_created << attrs
      end

      evaluator = DSPy::Evals.new(
        simple_program,
        metric: simple_metric,
        export_scores: true
      )

      examples = [
        { question: 'What is 6x7?', expected: '42' },
        { question: 'What is 2+2?', expected: '4' }
      ]

      evaluator.evaluate(examples, display_progress: false)

      # Should include a batch score
      batch_scores = scores_created.select { |s| s[:score_name].include?('batch') }
      expect(batch_scores).not_to be_empty

      DSPy.events.unsubscribe(subscription_id)
    end
  end

  describe 'score names' do
    it 'uses program class name in score name' do
      scores_created = []
      subscription_id = DSPy.events.subscribe('score.create') do |_name, attrs|
        scores_created << attrs
      end

      evaluator = DSPy::Evals.new(
        simple_program,
        metric: simple_metric,
        export_scores: true,
        score_name: 'accuracy'
      )

      examples = [{ question: 'What is 6x7?', expected: '42' }]
      evaluator.evaluate(examples, display_progress: false)

      expect(scores_created.any? { |s| s[:score_name] == 'accuracy' }).to be true

      DSPy.events.unsubscribe(subscription_id)
    end
  end

  describe 'trace_id propagation' do
    it 'attaches scores to the current trace' do
      scores_created = []
      subscription_id = DSPy.events.subscribe('score.create') do |_name, attrs|
        scores_created << attrs
      end

      trace_id = DSPy::Context.current[:trace_id]

      evaluator = DSPy::Evals.new(
        simple_program,
        metric: simple_metric,
        export_scores: true
      )

      examples = [{ question: 'What is 6x7?', expected: '42' }]
      evaluator.evaluate(examples, display_progress: false)

      expect(scores_created.all? { |s| s[:trace_id] == trace_id }).to be true

      DSPy.events.unsubscribe(subscription_id)
    end
  end
end
