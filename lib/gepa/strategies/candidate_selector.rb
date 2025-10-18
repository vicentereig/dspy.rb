# frozen_string_literal: true

require 'sorbet-runtime'

module GEPA
  module Strategies
    class ParetoCandidateSelector
      extend T::Sig

      sig { params(rng: T.nilable(Random), telemetry: T.nilable(T.untyped)).void }
      def initialize(rng: nil, telemetry: nil)
        @rng = rng || Random.new(0)
        @telemetry = telemetry
      end

      sig { params(state: GEPA::Core::State).returns(Integer) }
      def select_candidate_idx(state)
        ensure_lengths!(state)
        with_span('gepa.strategies.candidate_selector', strategy: 'pareto') do
          scores = state.per_program_tracked_scores.each_with_index.to_h { |score, idx| [idx, score] }
          GEPA::Utils::Pareto.select_program_candidate_from_pareto_front(
            state.program_at_pareto_front_valset,
            scores,
            @rng
          )
        end
      end

      private

      sig { params(state: GEPA::Core::State).void }
      def ensure_lengths!(state)
        return if state.per_program_tracked_scores.length == state.program_candidates.length

        raise ArgumentError, 'per_program_tracked_scores and program_candidates length mismatch'
      end

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
      def with_span(operation, attrs = {}, &block)
        telemetry.with_span(operation, attrs, &block)
      end
    end

    class CurrentBestCandidateSelector
      extend T::Sig

      sig { params(telemetry: T.nilable(T.untyped)).void }
      def initialize(telemetry: nil)
        @telemetry = telemetry
      end

      sig { params(state: GEPA::Core::State).returns(Integer) }
      def select_candidate_idx(state)
        ensure_lengths!(state)
        with_span('gepa.strategies.candidate_selector', strategy: 'current_best') do
          GEPA::Utils::Pareto.idxmax(state.per_program_tracked_scores)
        end
      end

      private

      sig { params(state: GEPA::Core::State).void }
      def ensure_lengths!(state)
        return if state.per_program_tracked_scores.length == state.program_candidates.length

        raise ArgumentError, 'per_program_tracked_scores and program_candidates length mismatch'
      end

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
      def with_span(operation, attrs = {}, &block)
        telemetry.with_span(operation, attrs, &block)
      end
    end
  end
end
