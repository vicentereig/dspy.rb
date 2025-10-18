# frozen_string_literal: true

require 'sorbet-runtime'

module GEPA
  module Strategies
    class RoundRobinReflectionComponentSelector
      extend T::Sig

      sig { params(telemetry: T.nilable(T.untyped)).void }
      def initialize(telemetry: nil)
        @telemetry = telemetry
      end

      sig do
        params(
          state: GEPA::Core::State,
          trajectories: T::Array[T.untyped],
          subsample_scores: T::Array[Float],
          candidate_idx: Integer,
          candidate: T::Hash[String, String]
        ).returns(T::Array[String])
      end
      def select_modules(state, trajectories, subsample_scores, candidate_idx, candidate)
        with_span(
          'gepa.strategies.component_selector',
          strategy: 'round_robin',
          candidate_idx: candidate_idx
        ) do
          predictor_id = state.named_predictor_id_to_update_next_for_program_candidate[candidate_idx]
          state.named_predictor_id_to_update_next_for_program_candidate[candidate_idx] =
            (predictor_id + 1) % state.list_of_named_predictors.length

          [state.list_of_named_predictors[predictor_id]]
        end
      end

      private

      sig { returns(T.untyped) }
      def telemetry
        @telemetry || GEPA::Telemetry
      end

      sig do
        params(
          operation: String,
          attrs: T::Hash[Symbol, T.untyped],
          block: T.proc.returns(T.untyped)
        ).returns(T.untyped)
      end
      def with_span(operation, attrs, &block)
        telemetry.with_span(operation, attrs, &block)
      end
    end
  end
end
