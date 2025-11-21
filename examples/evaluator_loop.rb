#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Requirements-Aware Evaluator Loop for AI SDR posts
#
# This example turns the original “slop generator” into a requirements-driven
# SDR post generator. A generator drafts outbound copy, an evaluator checks
# explicit requirements plus quality, and the loop iterates until approval or
# the token budget is exhausted.

require 'dotenv'
require 'optparse'

Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

def ensure_api_key!(env_key)
  return if ENV[env_key]

  warn "Missing #{env_key}. Set it in .env or your shell before running this example."
  exit 1
end

GENERATOR_MODEL = ENV.fetch('DSPY_SDR_GENERATOR_MODEL', 'anthropic/claude-haiku-4-5-20251001')
EVALUATOR_MODEL = ENV.fetch('DSPY_SDR_EVALUATOR_MODEL', 'anthropic/claude-sonnet-4-5-20250929')

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    GENERATOR_MODEL,
    api_key: ENV['ANTHROPIC_API_KEY'],
    structured_outputs: true
  )
end

DSPy::Observability.configure!

module EvaluatorLoop
  class Channel < T::Enum
    enums do
      LinkedIn = new('linkedin')
      Email = new('email')
      SlackCommunity = new('slack_community')
    end
  end

  class TonePreset < T::Enum
    enums do
      Consultative = new('consultative')
      Challenger = new('challenger')
      Playful = new('playful')
    end
  end

  class NarrativeGoal < T::Enum
    enums do
      ProblemAgitation = new('problem_agitation')
      CustomerProof = new('customer_proof')
      DiagnosticOffer = new('diagnostic_offer')
      BenchmarkDrop = new('benchmark_drop')
    end
  end

  class ProspectPersona < T::Struct
    const :title, String
    const :industry, String
    const :team_size, String
    const :pain_point, String
  end

  class OfferPackage < T::Struct
    const :name, String
    const :headline_benefit, String
    const :proof_point, String
    const :cta, String
    const :success_metrics, T::Array[String], default: []
  end

  class Requirement < T::Struct
    const :id, String
    const :statement, String
    const :weight, Integer, default: 1
  end

  class RequirementAssessment < T::Struct
    const :requirement_id, String
    const :met, T::Boolean
    const :commentary, T.nilable(String), default: nil
    const :weight, Integer, default: 1
  end

  class Recommendation < T::Struct
    const :message, String
    const :source_attempt, Integer, default: 0
    const :severity, String, default: 'info'
  end

  class EvaluationDecision < T::Enum
    enums do
      Approved = new('approved')
      NeedsRevision = new('needs_revision')
    end
  end

  class GenerateSdrPost < DSPy::Signature
    description 'Draft an outbound-ready SDR post anchored to explicit requirements.'

    input do
      const :persona, ProspectPersona,
        description: 'Buying persona context the copy must reference.'
      const :offer_package, OfferPackage,
        description: 'What the SDR is promoting, including CTA + proof.'
      const :requirements, T::Array[Requirement],
        description: 'Explicit checklist of statements the copy must cover.'
      const :tone, TonePreset, default: TonePreset::Consultative,
        description: 'Macro tone slider for the SDR voice.'
      const :channel, Channel, default: Channel::LinkedIn,
        description: 'Target posting channel so the format stays aligned.'
      const :narrative_goal, NarrativeGoal, default: NarrativeGoal::ProblemAgitation,
        description: 'Primary narrative arc (agitate a pain, drop benchmark, etc.).'
      const :recommendations, T::Array[Recommendation], default: [],
        description: 'Evaluator notes from previous attempts.'
    end

    output do
      const :post, String,
        description: 'Outbound-ready copy that addresses persona, offer, and requirements.'
      const :talking_points, T::Array[String],
        description: 'Bullet list the evaluator can reference when judging coverage.'
    end
  end

  class EvaluateSdrPost < DSPy::Signature
    description 'Score the SDR post, returning requirement coverage and refinement advice.'

    input do
      const :post, String, description: 'Latest draft from the generator.'
      const :persona, ProspectPersona, description: 'Target persona metadata.'
      const :offer_package, OfferPackage, description: 'Product/value props to reinforce.'
      const :requirements, T::Array[Requirement], description: 'Checklist the evaluator enforces.'
      const :tone, TonePreset, description: 'Requested tone slider.'
      const :channel, Channel, description: 'Channel-specific guidance (format, hashtags, etc.).'
      const :narrative_goal, NarrativeGoal, description: 'Narrative arc the copy should follow.'
      const :recommendations, T::Array[Recommendation], description: 'Already-issued edits.'
      const :talking_points, T::Array[String], description: 'Context surfaced by the generator.'
      const :attempt, Integer, description: '1-indexed attempt number for tracing.'
    end

    output do
      const :decision, EvaluationDecision,
        description: 'Whether this draft can ship as-is or needs another pass.'
      const :feedback, String,
        description: 'Narrative explanation of the score + rationale.'
      const :recommendations, T::Array[Recommendation],
        description: 'Actionable deltas the generator should apply next.'
      const :requirement_assessments, T::Array[RequirementAssessment],
        description: 'Per-requirement coverage grading with optional notes.'
      const :compliance_score, Float,
        description: 'Evaluator self-score for quality/confidence in the draft.'
    end
  end

  class RequirementSummary < T::Struct
    const :covered_weight, Integer
    const :total_weight, Integer
    const :coverage_ratio, Float
  end

  class Revision < T::Struct
    const :attempt_number, Integer
    const :post, String
    const :decision, EvaluationDecision
    const :feedback, String
    const :recommendations, T::Array[Recommendation]
    const :compliance_score, Float
    const :requirement_summary, RequirementSummary
  end

  class RevisedPost < T::Struct
    const :final_post, String
    const :decision, EvaluationDecision
    const :attempts, Integer
    const :history, T::Array[Revision]
    const :token_budget_used, Integer
    const :token_budget_limit, Integer
    const :budget_exhausted, T::Boolean
    const :requirement_summary, RequirementSummary
  end

  class TokenBudgetTracker
    extend T::Sig

    sig { params(limit: Integer).void }
    def initialize(limit:)
      @limit = limit
      @used = T.let(0, Integer)
    end

    sig { returns(Integer) }
    attr_reader :limit

    sig { returns(Integer) }
    attr_reader :used

    sig do
      params(
        prompt_tokens: T.nilable(Integer),
        completion_tokens: T.nilable(Integer),
        total_tokens: T.nilable(Integer)
      ).void
    end
    def track(prompt_tokens:, completion_tokens:, total_tokens: nil)
      prompt = prompt_tokens || 0
      completion = completion_tokens || 0
      increment = prompt + completion
      increment = total_tokens if increment.zero? && total_tokens
      @used += increment
    end

    sig { returns(T::Boolean) }
    def exhausted?
      @used >= @limit
    end

    sig { returns(Integer) }
    def remaining
      [@limit - @used, 0].max
    end
  end

  class SdrPostLoop < DSPy::Module
    extend T::Sig

    DEFAULT_TOKEN_BUDGET = 9_000
    SELF_SCORE_THRESHOLD = 0.9
    REQUIREMENT_COVERAGE_THRESHOLD = 0.85

    subscribe 'lm.tokens', :count_tokens, scope: DSPy::Module::SubcriptionScope::Descendants

    sig do
      params(
        generator: DSPy::Predict,
        evaluator: DSPy::Predict,
        token_budget_limit: Integer
      ).void
    end
    def initialize(generator:, evaluator:, token_budget_limit: DEFAULT_TOKEN_BUDGET)
      super()
      @generator = generator
      @evaluator = evaluator
      @token_budget_limit = token_budget_limit
    end

    sig { override.params(input_values: T.untyped).returns(RevisedPost) }
    def forward(**input_values)
      requirements = T.let(input_values.fetch(:requirements, []), T::Array[Requirement])
      recommendations = T.let(input_values.fetch(:recommendations, []), T::Array[Recommendation])
      history = []
      final_post = ''
      final_decision = EvaluationDecision::NeedsRevision
      attempt_number = 0
      tracker = TokenBudgetTracker.new(limit: @token_budget_limit)
      @active_budget_tracker = tracker
      latest_summary = RequirementSummary.new(
        covered_weight: 0,
        total_weight: total_requirement_weight(requirements),
        coverage_ratio: requirements.empty? ? 1.0 : 0.0
      )

      while tracker.remaining.positive?
        attempt_number += 1
        draft = @generator.call(**input_values.merge(requirements: requirements, recommendations: recommendations))

        evaluation = @evaluator.call(
          post: draft.post,
          persona: input_values[:persona],
          offer_package: input_values[:offer_package],
          requirements: requirements,
          tone: input_values[:tone],
          channel: input_values[:channel],
          narrative_goal: input_values[:narrative_goal],
          recommendations: recommendations,
          talking_points: draft.talking_points,
          attempt: attempt_number
        )

        assessments = evaluation.requirement_assessments || []
        latest_summary = summarize_requirements(assessments, requirements)

        history << Revision.new(
          attempt_number: attempt_number,
          post: draft.post,
          decision: evaluation.decision,
          feedback: evaluation.feedback,
          recommendations: evaluation.recommendations || [],
          compliance_score: clamp_score(evaluation.compliance_score),
          requirement_summary: latest_summary
        )

        final_post = draft.post
        final_decision = evaluation.decision
        recommendations = evaluation.recommendations || []

        if final_decision == EvaluationDecision::Approved && history.last.compliance_score < SELF_SCORE_THRESHOLD
          recommendations = recommendations.dup
          recommendations << Recommendation.new(
            message: format(
              'Compliance score %.2f fell below required %.1f. Tighten the copy before approval.',
              history.last.compliance_score,
              SELF_SCORE_THRESHOLD
            ),
            source_attempt: attempt_number,
            severity: 'warn'
          )
          final_decision = EvaluationDecision::NeedsRevision
        end

        if !requirements.empty? && final_decision == EvaluationDecision::Approved &&
           latest_summary.coverage_ratio < REQUIREMENT_COVERAGE_THRESHOLD
          recommendations = recommendations.dup
          recommendations << Recommendation.new(
            message: format(
              'Requirement coverage at %.1f%% is below the %.0f%% threshold. Address missed checkpoints.',
              latest_summary.coverage_ratio * 100,
              REQUIREMENT_COVERAGE_THRESHOLD * 100
            ),
            source_attempt: attempt_number,
            severity: 'warn'
          )
          final_decision = EvaluationDecision::NeedsRevision
        end

        break if final_decision == EvaluationDecision::Approved || tracker.exhausted?
      end

      RevisedPost.new(
        final_post: final_post,
        decision: final_decision,
        attempts: history.size,
        history: history,
        token_budget_used: tracker.used,
        token_budget_limit: @token_budget_limit,
        budget_exhausted: tracker.exhausted?,
        requirement_summary: latest_summary
      )
    ensure
      @active_budget_tracker = nil
    end

    private

    sig { params(score: T.nilable(Float)).returns(Float) }
    def clamp_score(score)
      return 0.0 if score.nil? || score.nan?

      [[score, 0.0].max, 1.0].min
    end

    sig { params(requirements: T::Array[Requirement]).returns(Integer) }
    def total_requirement_weight(requirements)
      requirements.sum(&:weight)
    end

    sig do
      params(assessments: T::Array[RequirementAssessment], requirements: T::Array[Requirement]).
        returns(RequirementSummary)
    end
    def summarize_requirements(assessments, requirements)
      total_weight = total_requirement_weight(requirements)
      return RequirementSummary.new(covered_weight: 0, total_weight: 0, coverage_ratio: 1.0) if total_weight.zero?

      weights = requirements.each_with_object({}) { |req, memo| memo[req.id] = req.weight }

      covered_weight = assessments.sum do |assessment|
        next 0 unless assessment.met

        weights.fetch(assessment.requirement_id, assessment.weight || 1)
      end

      coverage_ratio = covered_weight.to_f / total_weight
      RequirementSummary.new(
        covered_weight: covered_weight,
        total_weight: total_weight,
        coverage_ratio: [[coverage_ratio, 0.0].max, 1.0].min
      )
    end

    sig { params(_event_name: String, attributes: T::Hash[T.untyped, T.untyped]).void }
    def count_tokens(_event_name, attributes)
      tracker = @active_budget_tracker
      return unless tracker

      prompt = attributes[:input_tokens] || attributes['input_tokens'] || attributes['gen_ai.usage.prompt_tokens']
      completion = attributes[:output_tokens] || attributes['output_tokens'] || attributes['gen_ai.usage.completion_tokens']
      total = attributes[:total_tokens] || attributes['total_tokens'] || attributes['gen_ai.usage.total_tokens']

      tracker.track(
        prompt_tokens: prompt&.to_i,
        completion_tokens: completion&.to_i,
        total_tokens: total&.to_i
      )
    end
  end

  module Demo
    module_function

    CLI_TONE_OPTIONS = {
      'consultative' => TonePreset::Consultative,
      'challenger' => TonePreset::Challenger,
      'playful' => TonePreset::Playful
    }.freeze

    CLI_CHANNEL_OPTIONS = {
      'linkedin' => Channel::LinkedIn,
      'email' => Channel::Email,
      'slack' => Channel::SlackCommunity,
      'slack_community' => Channel::SlackCommunity
    }.freeze

    CLI_GOAL_OPTIONS = {
      'problem' => NarrativeGoal::ProblemAgitation,
      'problem_agitation' => NarrativeGoal::ProblemAgitation,
      'proof' => NarrativeGoal::CustomerProof,
      'customer_proof' => NarrativeGoal::CustomerProof,
      'diagnostic' => NarrativeGoal::DiagnosticOffer,
      'benchmark' => NarrativeGoal::BenchmarkDrop
    }.freeze

    def run!(inputs: default_inputs, token_budget_limit: nil)
      ensure_api_key!('ANTHROPIC_API_KEY')

      loop_module = build_loop_module(token_budget_limit: token_budget_limit)

      result = loop_module.call(**inputs)

      puts "Final decision: #{result.decision.serialize} after #{result.attempts} attempt(s)"
      puts "Post (#{inputs[:channel].serialize}):\n#{result.final_post}"
      puts format(
        'Requirement coverage: %d/%d (%.1f%%)',
        result.requirement_summary.covered_weight,
        result.requirement_summary.total_weight,
        result.requirement_summary.coverage_ratio * 100
      )
      puts "Budget: #{result.token_budget_used}/#{result.token_budget_limit} tokens (exhausted? #{result.budget_exhausted})"
      print_recommendations(result.history)

      result
    end

    def run_from_cli!(argv)
      options = parse_cli_options(argv)
      inputs = apply_overrides(default_inputs, options)

      run!(
        inputs: inputs,
        token_budget_limit: options[:token_budget_limit]
      )
    end

    def build_loop_module(token_budget_limit: nil)
      generator = build_predictor(GenerateSdrPost, GENERATOR_MODEL)
      evaluator = build_predictor(EvaluateSdrPost, EVALUATOR_MODEL)

      limit = token_budget_limit || Integer(
        ENV.fetch(
          'DSPY_SDR_TOKEN_BUDGET',
          SdrPostLoop::DEFAULT_TOKEN_BUDGET.to_s
        )
      )

      SdrPostLoop.new(
        generator: generator,
        evaluator: evaluator,
        token_budget_limit: limit
      )
    end

    def build_predictor(signature_class, model_id)
      DSPy::Predict.new(signature_class).configure do |config|
        config.lm = DSPy::LM.new(
          model_id,
          api_key: ENV['ANTHROPIC_API_KEY']
        )
      end
    end

    def default_inputs
      {
        persona: ProspectPersona.new(
          title: 'VP of Revenue Operations',
          industry: 'SaaS',
          team_size: '45-person go-to-market org',
          pain_point: 'manual pipeline hygiene slowing QBR prep'
        ),
        offer_package: OfferPackage.new(
          name: 'Playbook Copilot',
          headline_benefit: 'AI SDR that drafts outbound posts from CRM alerts within 3 minutes',
          proof_point: 'customers see 28% faster meeting creation when RevOps pushes a hot account alert',
          cta: 'drop a current outbound blocker and we will share a personalized call outline',
          success_metrics: ['meetings per rep', 'reply rate to hot account posts']
        ),
        requirements: [
          Requirement.new(
            id: 'pain_callout',
            statement: 'Name the manual hygiene drag and quantify its cost to pipeline reviews.',
            weight: 2
          ),
          Requirement.new(
            id: 'proof_point',
            statement: 'Reference a customer proof metric (percent lift or cycle time).',
            weight: 1
          ),
          Requirement.new(
            id: 'cta_specific',
            statement: 'Close with a CTA inviting the prospect to share a blocker screenshot for teardown.',
            weight: 2
          )
        ],
        tone: TonePreset::Consultative,
        channel: Channel::LinkedIn,
        narrative_goal: NarrativeGoal::ProblemAgitation
      }
    end

    def parse_cli_options(argv)
      options = {
        persona: {},
        offer_package: {},
        requirements: [],
        tone: nil,
        channel: nil,
        narrative_goal: nil,
        token_budget_limit: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: bundle exec ruby examples/evaluator_loop.rb [options]'
        opts.separator ''
        opts.separator 'Persona overrides:'

        opts.on('--title TITLE', 'Persona title (e.g., VP of RevOps)') do |value|
          options[:persona][:title] = value
        end

        opts.on('--industry INDUSTRY', 'Persona industry description') do |value|
          options[:persona][:industry] = value
        end

        opts.on('--team-size SIZE', 'Persona team size blurb') do |value|
          options[:persona][:team_size] = value
        end

        opts.on('--pain-point TEXT', 'Primary pain point to agitate') do |value|
          options[:persona][:pain_point] = value
        end

        opts.separator ''
        opts.separator 'Offer overrides:'

        opts.on('--offer-name NAME', 'Name of the offer/package') do |value|
          options[:offer_package][:name] = value
        end

        opts.on('--benefit TEXT', 'Headline benefit statement') do |value|
          options[:offer_package][:headline_benefit] = value
        end

        opts.on('--proof TEXT', 'Proof point the SDR should cite') do |value|
          options[:offer_package][:proof_point] = value
        end

        opts.on('--cta TEXT', 'Call-to-action text to enforce') do |value|
          options[:offer_package][:cta] = value
        end

        opts.on('--metrics LIST', 'Comma-separated success metrics to mention') do |value|
          options[:offer_package][:success_metrics] = value.split(',').map(&:strip)
        end

        opts.separator ''
        opts.separator 'Requirements:'

        opts.on('--requirement SPEC', 'Add requirement as id|statement|weight (weight optional)') do |value|
          options[:requirements] << value
        end

        opts.separator ''
        opts.separator 'Tone + runtime:'

        opts.on('--tone TONE', "Tone preset (#{CLI_TONE_OPTIONS.keys.join(', ')})") do |value|
          options[:tone] = fetch_enum(value, CLI_TONE_OPTIONS, 'tone')
        end

        opts.on('--channel CHANNEL', "Channel (#{CLI_CHANNEL_OPTIONS.keys.join(', ')})") do |value|
          options[:channel] = fetch_enum(value, CLI_CHANNEL_OPTIONS, 'channel')
        end

        opts.on('--goal GOAL', "Narrative goal (#{CLI_GOAL_OPTIONS.keys.join(', ')})") do |value|
          options[:narrative_goal] = fetch_enum(value, CLI_GOAL_OPTIONS, 'goal')
        end

        opts.on('--token-budget TOKENS', Integer, 'Override token budget limit') do |value|
          options[:token_budget_limit] = value
        end

        opts.on('-h', '--help', 'Show this help') do
          puts opts
          exit 0
        end
      end

      parser.parse!(argv)
      options
    end

    def fetch_enum(raw_value, mapping, field)
      enum = mapping[raw_value.to_s.downcase]
      raise OptionParser::InvalidArgument, "Unknown #{field}: #{raw_value}" unless enum

      enum
    end

    def parse_requirement(value)
      id, statement, weight = value.split('|', 3)
      raise OptionParser::InvalidArgument, 'Requirement spec must include id|statement' unless id && statement

      Requirement.new(
        id: id.strip,
        statement: statement.strip,
        weight: weight ? Integer(weight) : 1
      )
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, "Invalid requirement weight: #{e.message}"
    end

    def apply_overrides(inputs, options)
      updated = inputs.dup

      unless options[:persona].empty?
        persona = updated[:persona]
        updated[:persona] = ProspectPersona.new(
          title: options[:persona].fetch(:title, persona.title),
          industry: options[:persona].fetch(:industry, persona.industry),
          team_size: options[:persona].fetch(:team_size, persona.team_size),
          pain_point: options[:persona].fetch(:pain_point, persona.pain_point)
        )
      end

      unless options[:offer_package].empty?
        offer = updated[:offer_package]
        updated[:offer_package] = OfferPackage.new(
          name: options[:offer_package].fetch(:name, offer.name),
          headline_benefit: options[:offer_package].fetch(:headline_benefit, offer.headline_benefit),
          proof_point: options[:offer_package].fetch(:proof_point, offer.proof_point),
          cta: options[:offer_package].fetch(:cta, offer.cta),
          success_metrics: options[:offer_package].fetch(:success_metrics, offer.success_metrics)
        )
      end

      unless options[:requirements].empty?
        updated[:requirements] = options[:requirements].map { |spec| parse_requirement(spec) }
      end

      updated[:tone] = options[:tone] if options[:tone]
      updated[:channel] = options[:channel] if options[:channel]
      updated[:narrative_goal] = options[:narrative_goal] if options[:narrative_goal]

      updated
    end

    def print_recommendations(history)
      entries = history.flat_map do |attempt|
        notes = []
        summary = attempt.requirement_summary
        coverage = format('coverage %.1f%%', summary.coverage_ratio * 100)
        notes << "Attempt #{attempt.attempt_number} (#{attempt.decision.serialize}, #{coverage}): #{attempt.feedback}"

        attempt.recommendations.each do |rec|
          notes << format(
            'Attempt %d [%s]: %s',
            attempt.attempt_number,
            rec.severity || 'info',
            rec.message
          )
        end

        notes
      end

      return if entries.empty?

      puts "\nEvaluator recommendations:"
      entries.each { |line| puts "- #{line}" }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  EvaluatorLoop::Demo.run_from_cli!(ARGV)
  DSPy::Observability.flush!
end
