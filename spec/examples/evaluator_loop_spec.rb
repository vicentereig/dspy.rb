require 'spec_helper'
require_relative '../../examples/evaluator_loop'

RSpec.describe EvaluatorLoop::SdrPostLoop do
  let(:persona) do
    EvaluatorLoop::ProspectPersona.new(
      title: 'VP of Revenue Operations',
      industry: 'SaaS',
      team_size: '45-person GTM',
      pain_point: 'manual pipeline hygiene slowing QBR prep'
    )
  end

  let(:offer_package) do
    EvaluatorLoop::OfferPackage.new(
      name: 'Playbook Copilot',
      headline_benefit: 'AI SDR that drafts outbound posts from CRM alerts within 3 minutes',
      proof_point: '28% faster meeting creation after hot account alerts',
      cta: 'drop a current outbound blocker and we will share a personalized call outline',
      success_metrics: ['meetings per rep']
    )
  end

  let(:requirements) do
    [
      EvaluatorLoop::Requirement.new(id: 'pain', statement: 'Call out the pipeline hygiene drag', weight: 2),
      EvaluatorLoop::Requirement.new(id: 'proof', statement: 'Mention a proof metric', weight: 1)
    ]
  end

  let(:generator_model) { 'anthropic/claude-3-5-haiku-20241022' }
  let(:evaluator_model) { 'anthropic/claude-3-5-sonnet-20241022' }

  def build_predictor(signature_class, model_id)
    predictor = DSPy::Predict.new(signature_class)
    predictor.configure do |config|
      config.lm = DSPy::LM.new(model_id, api_key: ENV['ANTHROPIC_API_KEY'])
    end
    predictor
  end

  def build_loop(token_budget_limit: described_class::DEFAULT_TOKEN_BUDGET)
    generator = build_predictor(EvaluatorLoop::GenerateSdrPost, generator_model)
    evaluator = build_predictor(EvaluatorLoop::EvaluateSdrPost, evaluator_model)

    described_class.new(
      generator: generator,
      evaluator: evaluator,
      token_budget_limit: token_budget_limit
    )
  end

  before do
    ENV['ANTHROPIC_API_KEY'] ||= 'test-anthropic-key'
  end

  it 'approves when evaluator and coverage meet thresholds' do
    generator = instance_double('DSPy::Predict')
    evaluator = instance_double('DSPy::Predict')

    draft = Struct.new(:post, :talking_points).new('draft 1', ['hook'])
    allow(generator).to receive(:call).and_return(draft)

    assessment = EvaluatorLoop::RequirementAssessment.new(
      requirement_id: 'pain', met: true, commentary: nil, weight: 2
    )
    allow(evaluator).to receive(:call).and_return(
      Struct.new(:decision, :feedback, :recommendations, :requirement_assessments, :compliance_score).new(
        EvaluatorLoop::EvaluationDecision::Approved,
        'covers pain + proof',
        [],
        [assessment],
        0.95
      )
    )

    loop_module = described_class.new(generator: generator, evaluator: evaluator, token_budget_limit: 500)

    result = loop_module.call(
      persona: persona,
      offer_package: offer_package,
      requirements: requirements,
      tone: EvaluatorLoop::TonePreset::Consultative,
      channel: EvaluatorLoop::Channel::LinkedIn,
      narrative_goal: EvaluatorLoop::NarrativeGoal::ProblemAgitation
    )

    expect(result.decision).to eq(EvaluatorLoop::EvaluationDecision::Approved)
    expect(result.attempts).to eq(1)
    expect(result.requirement_summary.coverage_ratio).to be > 0.8
  end

  it 'halts immediately when budget is zero' do
    loop_module = build_loop(token_budget_limit: 0)

    result = loop_module.call(
      persona: persona,
      offer_package: offer_package,
      requirements: requirements,
      tone: EvaluatorLoop::TonePreset::Consultative,
      channel: EvaluatorLoop::Channel::LinkedIn,
      narrative_goal: EvaluatorLoop::NarrativeGoal::ProblemAgitation
    )

    expect(result.attempts).to eq(0)
    expect(result.budget_exhausted).to be(true)
    expect(result.decision).to eq(EvaluatorLoop::EvaluationDecision::NeedsRevision)
  end

  it 'forces another pass when compliance score is below threshold' do
    generator = instance_double('DSPy::Predict')
    evaluator = instance_double('DSPy::Predict')

    draft = Struct.new(:post, :talking_points).new('first draft', ['hook'])
    allow(generator).to receive(:call).and_return(draft, draft)

    low_score = Struct.new(:decision, :feedback, :recommendations, :requirement_assessments, :compliance_score).new(
      EvaluatorLoop::EvaluationDecision::Approved,
      'good but light on proof',
      [],
      [],
      0.72
    )
    high_score = Struct.new(:decision, :feedback, :recommendations, :requirement_assessments, :compliance_score).new(
      EvaluatorLoop::EvaluationDecision::Approved,
      'ship it',
      [],
      [],
      0.95
    )

    allow(evaluator).to receive(:call).and_return(low_score, high_score)

    loop_module = described_class.new(generator: generator, evaluator: evaluator, token_budget_limit: 500)

    result = loop_module.call(
      persona: persona,
      offer_package: offer_package,
      requirements: [],
      tone: EvaluatorLoop::TonePreset::Consultative,
      channel: EvaluatorLoop::Channel::LinkedIn,
      narrative_goal: EvaluatorLoop::NarrativeGoal::ProblemAgitation
    )

    expect(result.decision).to eq(EvaluatorLoop::EvaluationDecision::Approved)
    expect(result.attempts).to eq(2)
    expect(generator).to have_received(:call).twice
    expect(evaluator).to have_received(:call).twice
  end
end
