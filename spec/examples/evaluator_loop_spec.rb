require 'spec_helper'
require_relative '../../examples/evaluator_loop'

RSpec.describe EvaluatorLoop::LinkedInSlopLoop do
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
      config.lm = DSPy::LM.new(
        model_id,
        api_key: ENV['ANTHROPIC_API_KEY']
      )
    end
    predictor
  end

  def build_loop(token_budget_limit: described_class::DEFAULT_TOKEN_BUDGET)
    generator = build_predictor(EvaluatorLoop::GenerateLinkedInArticle, generator_model)
    evaluator = build_predictor(EvaluatorLoop::EvaluateLinkedInArticle, evaluator_model)

    described_class.new(
      generator: generator,
      evaluator: evaluator,
      token_budget_limit: token_budget_limit
    )
  end

  before do
    ENV['ANTHROPIC_API_KEY'] ||= 'test-anthropic-key'
  end

  it 'approves within the default budget', vcr: { cassette_name: 'examples/evaluator_loop/two_iterations' } do
    loop_module = build_loop

    result = loop_module.call(
      topic_seed: topic_seed,
      vibe_toggles: vibe_toggles,
      structure_template: structure_template
    )

    expect(result.decision).to eq(EvaluatorLoop::EvaluationDecision::Approved)
    expect(result.attempts).to eq(2)
    expect(result.budget_exhausted).to be(false)
    expect(result.token_budget_limit).to eq(described_class::DEFAULT_TOKEN_BUDGET)
    expect(result.token_budget_used).to eq(1_728)
  end

  it 'halts when the budget is exhausted mid-loop', vcr: { cassette_name: 'examples/evaluator_loop/two_iterations' } do
    loop_module = build_loop(token_budget_limit: 800)

    result = loop_module.call(
      topic_seed: topic_seed,
      vibe_toggles: vibe_toggles,
      structure_template: structure_template
    )

    expect(result.decision).to eq(EvaluatorLoop::EvaluationDecision::NeedsRevision)
    expect(result.attempts).to eq(1)
    expect(result.budget_exhausted).to be(true)
    expect(result.token_budget_used).to be > 0
    expect(result.token_budget_limit).to eq(800)
  end

  it 'requires evaluator-provided self_score to exceed the threshold before final approval' do
    generator = DSPy::Predict.new(EvaluatorLoop::GenerateLinkedInArticle)
    evaluator = DSPy::Predict.new(EvaluatorLoop::EvaluateLinkedInArticle)

    first_draft = Struct.new(:post, :hooks).new('first draft', ['hook'])
    second_draft = Struct.new(:post, :hooks).new('second draft', ['hook'])

    allow(generator).to receive(:call).and_return(first_draft, second_draft)

    evaluation_struct = Struct.new(:decision, :feedback, :recommendations, :self_score)
    allow(evaluator).to receive(:call).and_return(
      evaluation_struct.new(
        EvaluatorLoop::EvaluationDecision::Approved,
        'good bones, but score low',
        [],
        0.72
      ),
      evaluation_struct.new(
        EvaluatorLoop::EvaluationDecision::Approved,
        'ship it',
        [],
        0.95
      )
    )

    loop_module = described_class.new(
      generator: generator,
      evaluator: evaluator,
      token_budget_limit: described_class::DEFAULT_TOKEN_BUDGET
    )

    result = loop_module.call(
      topic_seed: topic_seed,
      vibe_toggles: vibe_toggles,
      structure_template: structure_template
    )

    expect(result.decision).to eq(EvaluatorLoop::EvaluationDecision::Approved)
    expect(result.attempts).to eq(2)
    expect(result.history.last.self_score).to be >= EvaluatorLoop::LinkedInSlopLoop::SELF_SCORE_THRESHOLD
    expect(generator).to have_received(:call).twice
    expect(evaluator).to have_received(:call).twice
  end
end
