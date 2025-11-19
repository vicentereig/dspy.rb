require 'spec_helper'
require_relative '../../examples/evaluator_loop'

RSpec.describe 'Evaluator loop evals' do
  before do
    ENV['ANTHROPIC_API_KEY'] ||= 'test-anthropic-key'
  end

  let(:topic_seed) do
    EvaluatorLoop::TopicSeed.new(
      phrase: 'AI hiring lessons',
      take: EvaluatorLoop::SlopTopicTake::Contrarian
    )
  end

  let(:vibe_toggles) do
    EvaluatorLoop::VibeToggles.new(
      cringe: EvaluatorLoop::VibeDial::Balanced,
      hustle: EvaluatorLoop::VibeDial::Maximal,
      vulnerability: EvaluatorLoop::VibeDial::Muted
    )
  end

  let(:structure_template) { EvaluatorLoop::StructureTemplate::StoryLessonCta }

  let(:generator_model) { 'anthropic/claude-3-5-haiku-20241022' }
  let(:evaluator_model) { 'anthropic/claude-3-5-sonnet-20241022' }

  def build_predictor(signature_class, model_id)
    predictor = DSPy::Predict.new(signature_class)
    predictor.configure do |config|
      config.lm = DSPy::LM.new(model_id, api_key: ENV['ANTHROPIC_API_KEY'])
    end
    predictor
  end

  def build_loop
    generator = build_predictor(EvaluatorLoop::GenerateLinkedInArticle, generator_model)
    evaluator = build_predictor(EvaluatorLoop::EvaluateLinkedInArticle, evaluator_model)

    EvaluatorLoop::LinkedInSlopLoop.new(
      generator: generator,
      evaluator: evaluator
    )
  end

  let(:metric) { EvaluatorLoop::Metrics.loop_efficiency_metric }

  it 'evaluates the loop end-to-end with DSPy::Evals', vcr: { cassette_name: 'examples/evaluator_loop/two_iterations' } do
    evaluator = DSPy::Evals.new(
      build_loop,
      metric: metric
    )

    results = evaluator.evaluate([
      {
        input: {
          topic_seed: topic_seed,
          vibe_toggles: vibe_toggles,
          structure_template: structure_template
        },
        expected: { decision: 'approved' }
      }
    ])

    expect(results.score).to be_within(0.1).of(86.5)
    expect(results.total_examples).to eq(1)
  end
end
