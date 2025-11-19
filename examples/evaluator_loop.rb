#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Evaluator-Optimizer Loop for LinkedIn Slop Generation
#
# This script showcases how to wire a generator/evaluator workflow in
# DSPy.rb. We iteratively draft a LinkedIn-style post (“slop”), ask an
# evaluator to judge tone/structure, and feed the feedback back into the
# generator until the evaluator approves the draft or we exhaust the
# iteration budget.

require 'dotenv'
require 'optparse'

Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

def ensure_api_key!(env_key)
  return if ENV[env_key]

  warn "Missing #{env_key}. Set it in .env or your shell before running this example."
  exit 1
end

GENERATOR_MODEL = ENV.fetch('DSPY_SLOP_GENERATOR_MODEL', 'anthropic/claude-haiku-4-5-20251001')
EVALUATOR_MODEL = ENV.fetch('DSPY_SLOP_EVALUATOR_MODEL', 'anthropic/claude-sonnet-4-5-20250929')

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    GENERATOR_MODEL,
    api_key: ENV['ANTHROPIC_API_KEY'],
    structured_outputs: true
  )
end

DSPy::Observability.configure!

module EvaluatorLoop
  class SlopTopicTake < T::Enum
    enums do
      Contrarian = new('contrarian')
      Supportive = new('supportive')
      LessonsLearned = new('lessons_learned')
    end
  end

  class TopicSeed < T::Struct
    const :phrase, String
    const :take, SlopTopicTake
  end

  class VibeDial < T::Enum
    enums do
      Muted = new('muted')
      Balanced = new('balanced')
      Maximal = new('maximal')
    end
  end

  class VibeToggles < T::Struct
    const :cringe, VibeDial, default: VibeDial::Balanced
    const :hustle, VibeDial, default: VibeDial::Balanced
    const :vulnerability, VibeDial, default: VibeDial::Balanced
  end

  class StructureTemplate < T::Enum
    enums do
      StoryLessonCta = new('story_lesson_cta')
      Listicle = new('listicle')
      QuestionHook = new('question_hook')
    end
  end

  class HashtagBand < T::Struct
    const :min, Integer, default: 2
    const :max, Integer, default: 5
    const :auto_brand, T::Boolean, default: true
  end

  class LengthMode < T::Enum
    enums do
      Standard = new('standard')
      Short = new('short')
      Extended = new('extended')
    end
  end

  class LengthCap < T::Struct
    const :mode, LengthMode, default: LengthMode::Standard
    const :tokens, T.nilable(Integer), default: nil
    const :characters, T.nilable(Integer), default: nil
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

  class GenerateLinkedInArticle < DSPy::Signature
    description "Draft a LinkedIn-style slop post that embraces a persona's preferences."

    input do
      const :topic_seed, TopicSeed
      const :vibe_toggles, VibeToggles
      const :structure_template, StructureTemplate
      const :hashtag_band, HashtagBand, default: HashtagBand.new
      const :length_cap, LengthCap, default: LengthCap.new
      const :recommendations, T::Array[Recommendation], default: []
    end

    output do
      const :post, String
      const :hooks, T::Array[String]
      const :self_score, Float
    end
  end

  class EvaluateLinkedInArticle < DSPy::Signature
    description "Score a generated post and provide actionable feedback."

    input do
      const :post, String
      const :topic_seed, TopicSeed
      const :vibe_toggles, VibeToggles
      const :structure_template, StructureTemplate
      const :hashtag_band, HashtagBand
      const :length_cap, LengthCap
      const :recommendations, T::Array[Recommendation]
      const :hooks, T::Array[String]
      const :self_score, Float
      const :attempt, Integer
    end

    output do
      const :decision, EvaluationDecision
      const :feedback, String
      const :recommendations, T::Array[Recommendation]
    end
  end

  class LoopAttempt < T::Struct
    const :attempt_number, Integer
    const :post, String
    const :decision, EvaluationDecision
    const :feedback, String
    const :recommendations, T::Array[Recommendation]
  end

  class LoopResult < T::Struct
    const :final_post, String
    const :decision, EvaluationDecision
    const :attempts, Integer
    const :history, T::Array[LoopAttempt]
    const :token_budget_used, Integer
    const :token_budget_limit, Integer
    const :budget_exhausted, T::Boolean
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

      if increment.zero? && total_tokens
        increment = total_tokens
      end

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

  class LinkedInSlopLoop < DSPy::Module
    extend T::Sig
    DEFAULT_TOKEN_BUDGET = 10_000
    SELF_SCORE_THRESHOLD = 0.9

    subscribe 'lm.tokens', :handle_lm_tokens, scope: DSPy::Module::SubcriptionScope::Descendants

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

    sig { override.params(input_values: T.untyped).returns(T.untyped) }
    def forward(**input_values)
      hashtag_band = input_values.fetch(:hashtag_band, HashtagBand.new)
      length_cap = input_values.fetch(:length_cap, LengthCap.new)
      recommendations = T.let(input_values.fetch(:recommendations, []), T::Array[Recommendation])
      history = []
      final_post = ''
      final_decision = EvaluationDecision::NeedsRevision
      attempt_number = 0
      tracker = TokenBudgetTracker.new(limit: @token_budget_limit)
      @active_budget_tracker = tracker

      while tracker.remaining.positive?
        attempt_number += 1
        generator_payload = input_values.merge(
          hashtag_band: hashtag_band,
          length_cap: length_cap,
          recommendations: recommendations
        )
        draft = @generator.call(**generator_payload)

        evaluation = @evaluator.call(
          post: draft.post,
          hooks: draft.hooks,
          self_score: draft.self_score,
          topic_seed: input_values[:topic_seed],
          vibe_toggles: input_values[:vibe_toggles],
          structure_template: input_values[:structure_template],
          hashtag_band: hashtag_band,
          length_cap: length_cap,
          recommendations: recommendations,
          attempt: attempt_number
        )

        history << LoopAttempt.new(
          attempt_number: attempt_number,
          post: draft.post,
          decision: evaluation.decision,
          feedback: evaluation.feedback,
          recommendations: evaluation.recommendations || []
        )

        final_post = draft.post
        final_decision = evaluation.decision
        recommendations = evaluation.recommendations

        if final_decision == EvaluationDecision::Approved && draft.self_score < SELF_SCORE_THRESHOLD
          recommendations = recommendations.dup
          recommendations << Recommendation.new(
            message: format(
              "Self-score %.1f is below required %.1f. Refine the post before approval.",
              draft.self_score,
              SELF_SCORE_THRESHOLD
            ),
            source_attempt: attempt_number,
            severity: 'warn'
          )
          final_decision = EvaluationDecision::NeedsRevision
        end

        break if final_decision == EvaluationDecision::Approved || tracker.exhausted?
      end

      LoopResult.new(
        final_post: final_post,
        decision: final_decision,
        attempts: history.size,
        history: history,
        token_budget_used: tracker.used,
        token_budget_limit: @token_budget_limit,
        budget_exhausted: tracker.exhausted?
      )
    ensure
      @active_budget_tracker = nil
    end

    private

    sig { params(_event_name: String, attributes: T::Hash[T.untyped, T.untyped]).void }
    def handle_lm_tokens(_event_name, attributes)
      tracker = @active_budget_tracker
      return unless tracker

      prompt = attributes[:input_tokens] ||
               attributes['input_tokens'] ||
               attributes['gen_ai.usage.prompt_tokens']
      completion = attributes[:output_tokens] ||
                   attributes['output_tokens'] ||
                   attributes['gen_ai.usage.completion_tokens']
      total = attributes[:total_tokens] ||
              attributes['total_tokens'] ||
              attributes['gen_ai.usage.total_tokens']

      tracker.track(
        prompt_tokens: prompt&.to_i,
        completion_tokens: completion&.to_i,
        total_tokens: total&.to_i
      )
    end
  end
end

module EvaluatorLoop
  module Metrics
    extend T::Sig

    APPROVAL_WEIGHT = 0.6
    SPEED_WEIGHT = 0.2
    BUDGET_WEIGHT = 0.2
    PASS_THRESHOLD = 0.75

    sig { params(result: T.nilable(LoopResult)).returns(Float) }
    def self.loop_efficiency_score(result)
      return 0.0 unless result

      quality = result.decision == EvaluationDecision::Approved ? 1.0 : 0.0
      speed = result.attempts.positive? ? 1.0 / result.attempts : 0.0

      budget_term = if result.token_budget_limit.positive?
                      1.0 - (result.token_budget_used.to_f / result.token_budget_limit)
                    else
                      0.0
                    end
      budget_term = [[budget_term, 0.0].max, 1.0].min

      score = (APPROVAL_WEIGHT * quality) +
              (SPEED_WEIGHT * speed) +
              (BUDGET_WEIGHT * budget_term)

      [[score, 0.0].max, 1.0].min
    end

    sig { returns(T.proc.params(arg0: T.untyped, arg1: T.nilable(LoopResult)).returns(T::Hash[Symbol, T.untyped])) }
    def self.loop_efficiency_metric
      lambda do |_example, result|
        score = loop_efficiency_score(result)
        {
          score: score,
          passed: score >= PASS_THRESHOLD
        }
      end
    end
  end

  module Demo
    module_function

    CLI_TAKE_OPTIONS = {
      'contrarian' => SlopTopicTake::Contrarian,
      'supportive' => SlopTopicTake::Supportive,
      'lessons' => SlopTopicTake::LessonsLearned,
      'lessons_learned' => SlopTopicTake::LessonsLearned
    }.freeze

    CLI_VIBE_OPTIONS = {
      'muted' => VibeDial::Muted,
      'balanced' => VibeDial::Balanced,
      'maximal' => VibeDial::Maximal,
      'max' => VibeDial::Maximal
    }.freeze

    CLI_STRUCTURE_OPTIONS = {
      'story' => StructureTemplate::StoryLessonCta,
      'story_lesson_cta' => StructureTemplate::StoryLessonCta,
      'listicle' => StructureTemplate::Listicle,
      'question' => StructureTemplate::QuestionHook,
      'question_hook' => StructureTemplate::QuestionHook
    }.freeze

    def run!(inputs: default_inputs, token_budget_limit: nil)
      ensure_api_key!('ANTHROPIC_API_KEY')

      loop_module = build_loop_module(token_budget_limit: token_budget_limit)

      result = loop_module.call(**inputs)

      puts "Final decision: #{result.decision.serialize} after #{result.attempts} attempt(s)"
      puts "Post:\n#{result.final_post}"
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
      generator = build_predictor(GenerateLinkedInArticle, GENERATOR_MODEL)
      evaluator = build_predictor(EvaluateLinkedInArticle, EVALUATOR_MODEL)

      limit = token_budget_limit || Integer(
        ENV.fetch(
          'DSPY_SLOP_TOKEN_BUDGET',
          LinkedInSlopLoop::DEFAULT_TOKEN_BUDGET.to_s
        )
      )

      LinkedInSlopLoop.new(
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
        topic_seed: TopicSeed.new(
          phrase: 'AI infra leadership offsite',
          take: SlopTopicTake::LessonsLearned
        ),
        vibe_toggles: VibeToggles.new(
          cringe: VibeDial::Balanced,
          hustle: VibeDial::Maximal,
          vulnerability: VibeDial::Balanced
        ),
        structure_template: StructureTemplate::StoryLessonCta
      }
    end

    def parse_cli_options(argv)
      options = {
        topic_phrase: nil,
        topic_take: nil,
        structure_template: nil,
        vibe_overrides: {},
        token_budget_limit: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: bundle exec ruby examples/evaluator_loop.rb [options]"
        opts.separator ""
        opts.separator "Input overrides:"

        opts.on("--topic PHRASE", "Override topic seed phrase") do |value|
          options[:topic_phrase] = value
        end

        opts.on("--take TAKE", "Topic take (#{CLI_TAKE_OPTIONS.keys.join(', ')})") do |value|
          options[:topic_take] = fetch_enum(value, CLI_TAKE_OPTIONS, 'take')
        end

        opts.on("--structure TEMPLATE", "Structure template (#{CLI_STRUCTURE_OPTIONS.keys.join(', ')})") do |value|
          options[:structure_template] = fetch_enum(value, CLI_STRUCTURE_OPTIONS, 'structure')
        end

        add_vibe_option(opts, :cringe, options)
        add_vibe_option(opts, :hustle, options)
        add_vibe_option(opts, :vulnerability, options)

        opts.separator ""
        opts.separator "Runtime controls:"

        opts.on("--token-budget TOKENS", Integer, "Override token budget limit") do |value|
          options[:token_budget_limit] = value
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit 0
        end
      end

      parser.parse!(argv)
      options
    end

    def add_vibe_option(opts, key, options)
      opts.on("--#{key} LEVEL", "Set #{key} vibe (#{CLI_VIBE_OPTIONS.keys.join(', ')})") do |value|
        options[:vibe_overrides][key] = fetch_enum(value, CLI_VIBE_OPTIONS, key.to_s)
      end
    end

    def fetch_enum(raw_value, mapping, field)
      enum = mapping[raw_value.to_s.downcase]
      raise OptionParser::InvalidArgument, "Unknown #{field}: #{raw_value}" unless enum

      enum
    end

    def apply_overrides(inputs, options)
      updated = inputs.dup

      if options[:topic_phrase] || options[:topic_take]
        seed = updated[:topic_seed]
        updated[:topic_seed] = TopicSeed.new(
          phrase: options[:topic_phrase] || seed.phrase,
          take: options[:topic_take] || seed.take
        )
      end

      if options[:structure_template]
        updated[:structure_template] = options[:structure_template]
      end

      unless options[:vibe_overrides].empty?
        vibes = updated[:vibe_toggles]
        updated[:vibe_toggles] = VibeToggles.new(
          cringe: options[:vibe_overrides].fetch(:cringe, vibes.cringe),
          hustle: options[:vibe_overrides].fetch(:hustle, vibes.hustle),
          vulnerability: options[:vibe_overrides].fetch(:vulnerability, vibes.vulnerability)
        )
      end

      updated
    end

    def print_recommendations(history)
      entries = history.flat_map do |attempt|
        attempt_notes = []
        unless attempt.feedback.to_s.strip.empty?
          attempt_notes << "Attempt #{attempt.attempt_number}: #{attempt.feedback}"
        end

        attempt.recommendations.each do |rec|
          attempt_notes << format(
            "Attempt %d [%s]: %s",
            attempt.attempt_number,
            rec.severity || 'info',
            rec.message
          )
        end

        attempt_notes
      end.compact

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
