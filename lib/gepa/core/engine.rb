# frozen_string_literal: true

require 'sorbet-runtime'

require_relative 'state'
require_relative 'result'
require_relative '../telemetry'

module GEPA
  module Core
    class Engine
      extend T::Sig

      sig do
        params(
          evaluator: T.proc.params(dataset: T::Array[T.untyped], candidate: T::Hash[String, String])
                           .returns([T::Array[T.untyped], T::Array[Float]]),
          valset: T::Array[T.untyped],
          seed_candidate: T::Hash[String, String],
          max_metric_calls: Integer,
          perfect_score: Float,
          seed: Integer,
          reflective_proposer: T.untyped,
          logger: T.untyped,
          experiment_tracker: T.untyped,
          merge_proposer: T.nilable(T.untyped),
          run_dir: T.nilable(String),
          track_best_outputs: T::Boolean,
          display_progress_bar: T::Boolean,
          telemetry: T.nilable(T.untyped),
          raise_on_exception: T::Boolean
        ).void
      end
      def initialize(
        evaluator:,
        valset:,
        seed_candidate:,
        max_metric_calls:,
        perfect_score:,
        seed:, # rubocop:disable Lint/UnusedMethodArgument -- kept for parity and future use
        reflective_proposer:,
        logger:,
        experiment_tracker:,
        merge_proposer: nil,
        run_dir: nil,
        track_best_outputs: false,
        display_progress_bar: false,
        telemetry: nil,
        raise_on_exception: true
      )
        @run_dir = run_dir
        @evaluator = evaluator
        @valset = valset
        @seed_candidate = seed_candidate
        @max_metric_calls = max_metric_calls
        @perfect_score = perfect_score
        @reflective_proposer = reflective_proposer
        @merge_proposer = merge_proposer
        @logger = logger
        @experiment_tracker = experiment_tracker
        @track_best_outputs = track_best_outputs
        @display_progress_bar = display_progress_bar
        @telemetry = telemetry || GEPA::Telemetry
        @raise_on_exception = raise_on_exception
      end

      sig { returns(GEPA::Core::State) }
      def run
        with_span('gepa.engine.run', max_metric_calls: @max_metric_calls) do
          state = GEPA::Core::State.initialize_gepa_state(
            run_dir: @run_dir,
            logger: @logger,
            seed_candidate: @seed_candidate,
            valset_evaluator: ->(candidate) { full_evaluator(candidate) },
            track_best_outputs: @track_best_outputs
          )

          @experiment_tracker.log_metrics({ base_program_full_valset_score: state.program_full_scores_val_set.first }, step: 0)

          if @merge_proposer
            @merge_proposer.last_iter_found_new_program = false
          end

          while state.total_num_evals < @max_metric_calls
            break unless iteration_step(state)
          end

          state.save(@run_dir)
          state
        end
      end

      private

      sig { params(state: GEPA::Core::State).returns(T::Boolean) }
      def iteration_step(state)
        state.i += 1
        trace_entry = { iteration: state.i }
        state.full_program_trace << trace_entry

        progress = false

        with_span('gepa.engine.iteration', iteration: state.i) do
          merge_result = process_merge_iteration(state)
          case merge_result
          when :accepted
            return true
          when :attempted
            return false
          end

          reflective_result = process_reflective_iteration(state)
          return false if reflective_result == :no_candidate
          progress = true if reflective_result == :accepted
        end

        progress
      rescue StandardError => e
        @logger.log("Iteration #{state.i}: Exception during optimization: #{e}")
        @logger.log(e.backtrace&.join("\n"))
        raise e if @raise_on_exception
        true
      end

      sig { params(state: GEPA::Core::State).returns(Symbol) }
      def process_merge_iteration(state)
        return :skipped unless @merge_proposer && @merge_proposer.use_merge

        if @merge_proposer.merges_due.positive? && @merge_proposer.last_iter_found_new_program
          proposal = @merge_proposer.propose(state)
          @merge_proposer.last_iter_found_new_program = false

          if proposal&.tag == 'merge'
            parent_sums = Array(proposal.subsample_scores_before).map(&:to_f)
            new_sum = Array(proposal.subsample_scores_after).map(&:to_f).sum

            if parent_sums.empty?
              @logger.log("Iteration #{state.i}: Missing parent subscores for merge proposal, skipping")
              return :handled
            end

            if new_sum >= parent_sums.max
              with_span('gepa.engine.full_evaluation', iteration: state.i) do
                run_full_evaluation(state, proposal.candidate, proposal.parent_program_ids)
              end
              @merge_proposer.merges_due -= 1
              @merge_proposer.total_merges_tested += 1
              return :accepted
            else
              @logger.log(
                "Iteration #{state.i}: Merge subsample score #{new_sum.round(4)} "\
                "did not beat parents #{parent_sums.map { |v| v.round(4) }}, skipping"
              )
              return :attempted
            end
          end
        end

        @merge_proposer.last_iter_found_new_program = false
        :skipped
      end

      sig { params(state: GEPA::Core::State).void }
      def process_reflective_iteration(state)
        proposal = @reflective_proposer.propose(state)
        unless proposal
          @logger.log("Iteration #{state.i}: Reflective mutation did not propose a new candidate")
          return :no_candidate
        end

        before = Array(proposal.subsample_scores_before).map(&:to_f)
        after = Array(proposal.subsample_scores_after).map(&:to_f)
        if after.empty? || after.sum <= before.sum
          @logger.log("Iteration #{state.i}: New subsample score is not better, skipping")
          return :skipped
        end

        with_span('gepa.engine.full_evaluation', iteration: state.i) do
          run_full_evaluation(state, proposal.candidate, proposal.parent_program_ids)
        end

        if @merge_proposer&.use_merge
          @merge_proposer.last_iter_found_new_program = true
          @merge_proposer.schedule_if_needed
        end

        :accepted
      end

      sig do
        params(state: GEPA::Core::State, new_program: T::Hash[String, String], parents: T::Array[Integer]).void
      end
      def run_full_evaluation(state, new_program, parents)
        outputs, scores = full_evaluator(new_program)
        avg_score = scores.sum / scores.length.to_f

        state.num_full_ds_evals += 1
        state.total_num_evals += scores.length

        state.update_state_with_new_program(
          parents,
          new_program,
          avg_score,
          outputs,
          scores,
          @run_dir,
          state.total_num_evals
        )

        @experiment_tracker.log_metrics({ new_program_full_score: avg_score }, step: state.i)
      end

      sig { params(candidate: T::Hash[String, String]).returns([T::Array[T.untyped], T::Array[Float]]) }
      def full_evaluator(candidate)
        @evaluator.call(@valset, candidate)
      end

      sig do
        params(operation: String, attrs: T::Hash[Symbol, T.untyped], block: T.proc.returns(T.untyped)).returns(T.untyped)
      end
      def with_span(operation, attrs = {}, &block)
        @telemetry.with_span(operation, attrs, &block)
      end
    end
  end
end
