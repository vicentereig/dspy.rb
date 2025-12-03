require 'spec_helper'
require_relative '../../examples/evaluator_loop'

RSpec.describe EvaluatorLoop::SalesPitchWriterLoop do
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

  let(:generator_model) { 'anthropic/claude-haiku-4-5-20251001' }
  let(:evaluator_model) { 'anthropic/claude-sonnet-4-5-20250929' }

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

  it 'runs multiple iterations with skeptical evaluator feedback',
     vcr: { cassette_name: 'examples/evaluator_loop/two_iterations' } do
    loop_module = build_loop

    result = loop_module.call(
      topic_seed: topic_seed,
      vibe_toggles: vibe_toggles,
      structure_template: structure_template
    )

    # Skeptical evaluator provides substantive feedback across iterations
    expect(result.attempts).to be >= 2
    expect(result.token_budget_limit).to eq(described_class::DEFAULT_TOKEN_BUDGET)

    # Verify substantive feedback was provided in each iteration
    result.history.each do |revision|
      expect(revision.feedback.length).to be > 50
    end
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
    expect(result.history.last.self_score).to be >= EvaluatorLoop::SalesPitchWriterLoop::SELF_SCORE_THRESHOLD
    expect(generator).to have_received(:call).twice
    expect(evaluator).to have_received(:call).twice
  end

  describe 'skeptical evaluator behavior' do
    let(:decent_post) do
      <<~POST
        Last week, I had a revelation about AI hiring.

        After interviewing 50+ candidates, I realized the best engineers
        aren't the ones with the most GitHub stars. They're the ones who
        ask "why" before "how."

        Here are 3 lessons I learned:
        1. Curiosity beats credentials
        2. Communication skills matter more than coding speed
        3. Culture fit isn't about beer pong

        What's your hot take on hiring in tech?

        #AIHiring #TechRecruitment #Leadership
      POST
    end

    def build_evaluator
      DSPy::ChainOfThought.new(EvaluatorLoop::EvaluateLinkedInArticle).configure do |config|
        config.lm = DSPy::LM.new(
          evaluator_model,
          api_key: ENV['ANTHROPIC_API_KEY']
        )
      end
    end

    it 'rejects first attempts and provides substantive criticism',
       vcr: { cassette_name: 'examples/evaluator_loop/skeptical_evaluation' } do
      evaluator = build_evaluator

      result = evaluator.call(
        post: decent_post,
        topic_seed: topic_seed,
        vibe_toggles: vibe_toggles,
        structure_template: structure_template,
        hashtag_band: EvaluatorLoop::HashtagBand.new,
        length_cap: EvaluatorLoop::LengthCap.new,
        recommendations: [],
        hooks: ['AI hiring revelation', 'Why before how'],
        attempt: 1,
        mindset: EvaluatorLoop::EditorMindset::Skeptical
      )

      # Skeptical evaluator should NOT approve on first attempt
      expect(result.decision).to eq(EvaluatorLoop::EvaluationDecision::NeedsRevision)

      # Should provide substantive feedback (not empty or generic)
      expect(result.feedback.length).to be > 50

      # Should provide actionable recommendations
      expect(result.recommendations).not_to be_empty
    end
  end
end
