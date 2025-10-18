# frozen_string_literal: true

require 'sorbet-runtime'

require_relative 'core/engine'
require_relative 'core/result'

module GEPA
  module_function

  sig do
    params(
      seed_candidate: T::Hash[String, String],
      trainset: T::Array[T.untyped],
      valset: T::Array[T.untyped],
      adapter: T.untyped,
      reflective_proposer: T.untyped,
      logger: T.untyped,
      experiment_tracker: T.untyped,
      max_metric_calls: Integer,
      telemetry: T.nilable(T.untyped)
    ).returns(GEPA::Core::Result)
  end
  def optimize(
    seed_candidate:,
    trainset:,
    valset:,
    adapter:,
    reflective_proposer:,
    logger:,
    experiment_tracker:,
    max_metric_calls:,
    telemetry: nil
  )
    evaluator = proc { |dataset, candidate| adapter.evaluate(dataset, candidate) }

    engine = GEPA::Core::Engine.new(
      run_dir: nil,
      evaluator: evaluator,
      valset: valset,
      seed_candidate: seed_candidate,
      max_metric_calls: max_metric_calls,
      perfect_score: Float::INFINITY,
      seed: 0,
      reflective_proposer: reflective_proposer,
      merge_proposer: nil,
      logger: logger,
      experiment_tracker: experiment_tracker,
      telemetry: telemetry || GEPA::Telemetry,
      track_best_outputs: false,
      display_progress_bar: false
    )

    state = engine.run
    GEPA::Core::Result.from_state(state)
  end
end

