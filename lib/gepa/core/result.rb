# frozen_string_literal: true

require 'json'
require 'set'
require 'sorbet-runtime'

module GEPA
  module Core
    # Snapshot of GEPA optimization output with helpers for common queries.
    class Result < T::Struct
      extend T::Sig

      const :candidates, T::Array[T::Hash[String, String]]
      const :parents, T::Array[T::Array[T.nilable(Integer)]]
      const :val_aggregate_scores, T::Array[Float]
      const :val_subscores, T::Array[T::Array[Float]]
      const :per_val_instance_best_candidates, T::Array[T::Array[Integer]]
      const :discovery_eval_counts, T::Array[Integer]
      const :best_outputs_valset, T.nilable(T::Array[T::Array[T::Array[T.untyped]]]), default: nil
      const :total_metric_calls, T.nilable(Integer), default: nil
      const :num_full_val_evals, T.nilable(Integer), default: nil
      const :run_dir, T.nilable(String), default: nil
      const :seed, T.nilable(Integer), default: nil

      sig { returns(Integer) }
      def num_candidates
        candidates.length
      end

      sig { returns(Integer) }
      def num_val_instances
        per_val_instance_best_candidates.length
      end

      sig { returns(Integer) }
      def best_idx
        val_aggregate_scores.each_with_index.max_by { |score, _i| score }&.last || 0
      end

      sig { returns(T::Hash[String, String]) }
      def best_candidate
        candidates.fetch(best_idx)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          candidates: candidates.map(&:dup),
          parents: parents.map(&:dup),
          val_aggregate_scores: val_aggregate_scores.dup,
          val_subscores: val_subscores.map(&:dup),
          best_outputs_valset: best_outputs_valset&.map { |arr| arr.map(&:dup) },
          per_val_instance_best_candidates: per_val_instance_best_candidates.map(&:dup),
          discovery_eval_counts: discovery_eval_counts.dup,
          total_metric_calls: total_metric_calls,
          num_full_val_evals: num_full_val_evals,
          run_dir: run_dir,
          seed: seed,
          best_idx: best_idx
        }
      end

      sig { returns(String) }
      def to_json(*_args)
        JSON.pretty_generate(to_h)
      end

      sig do
        params(
          state: T.untyped,
          run_dir: T.nilable(String),
          seed: T.nilable(Integer)
        ).returns(Result)
      end
      def self.from_state(state, run_dir: nil, seed: nil)
        new(
          candidates: state.program_candidates.map(&:dup),
          parents: state.parent_program_for_candidate.map(&:dup),
          val_aggregate_scores: state.program_full_scores_val_set.map(&:to_f),
          best_outputs_valset: state.respond_to?(:best_outputs_valset) ? state.best_outputs_valset&.map(&:dup) : nil,
          val_subscores: state.prog_candidate_val_subscores.map { |scores| scores.map(&:to_f) },
          per_val_instance_best_candidates: state.program_at_pareto_front_valset.map { |set| set.to_a },
          discovery_eval_counts: state.num_metric_calls_by_discovery.map(&:to_i),
          total_metric_calls: state.respond_to?(:total_num_evals) ? state.total_num_evals : nil,
          num_full_val_evals: state.respond_to?(:num_full_ds_evals) ? state.num_full_ds_evals : nil,
          run_dir: run_dir,
          seed: seed
        )
      end
    end
  end
end
