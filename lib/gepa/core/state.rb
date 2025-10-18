# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'
require 'sorbet-runtime'

require_relative '../utils/pareto'
require_relative '../telemetry'

module GEPA
  module Core
    class State
      extend T::Sig

      attr_accessor :i, :num_full_ds_evals, :total_num_evals
      attr_reader :program_candidates,
                  :parent_program_for_candidate,
                  :program_full_scores_val_set,
                  :program_at_pareto_front_valset,
                  :prog_candidate_val_subscores,
                  :list_of_named_predictors,
                  :named_predictor_id_to_update_next_for_program_candidate,
                  :num_metric_calls_by_discovery,
                  :full_program_trace,
                  :per_program_tracked_scores,
                  :pareto_front_valset,
                  :best_outputs_valset

      sig do
        params(
          seed_candidate: T::Hash[String, String],
          base_valset_eval_output: [T::Array[T.untyped], T::Array[Float]],
          track_best_outputs: T::Boolean
        ).void
      end
      def initialize(seed_candidate, base_valset_eval_output, track_best_outputs: false)
        outputs, scores = base_valset_eval_output
        raise ArgumentError, 'validation scores must not be empty' if scores.empty?

        valset_base_score = scores.sum / scores.length.to_f

        @program_candidates = [seed_candidate.dup]
        @program_full_scores_val_set = [valset_base_score]
        @per_program_tracked_scores = [valset_base_score]

        @pareto_front_valset = scores.dup
        @parent_program_for_candidate = [[nil]]
        @program_at_pareto_front_valset = Array.new(scores.length) { Set.new([0]) }

        @list_of_named_predictors = seed_candidate.keys
        @named_predictor_id_to_update_next_for_program_candidate = [0]

        @prog_candidate_val_subscores = [scores.dup]
        @num_metric_calls_by_discovery = [0]

        @best_outputs_valset = if track_best_outputs
          outputs.map { |output| [[0, output]] }
        end

        @full_program_trace = []
        @i = -1
        @num_full_ds_evals = 0
        @total_num_evals = 0
      end

      sig { returns(T::Boolean) }
      def consistent?
        size = @program_candidates.length
        raise 'program_full_scores_val_set mismatch' unless @program_full_scores_val_set.length == size
        raise 'per_program_tracked_scores mismatch' unless @per_program_tracked_scores.length == size
        raise 'parent_program_for_candidate mismatch' unless @parent_program_for_candidate.length == size
        raise 'named_predictor_id_to_update mismatch' unless @named_predictor_id_to_update_next_for_program_candidate.length == size
        raise 'prog_candidate_val_subscores mismatch' unless @prog_candidate_val_subscores.length == size
        raise 'num_metric_calls mismatch' unless @num_metric_calls_by_discovery.length == size
        raise 'pareto fronts length mismatch' unless @pareto_front_valset.length == @program_at_pareto_front_valset.length

        @program_at_pareto_front_valset.each do |front|
          front.each do |idx|
            raise 'pareto index out of range' unless idx < size
          end
        end
        true
      end

      sig { params(run_dir: T.nilable(String)).void }
      def save(run_dir)
        return if run_dir.nil?

        FileUtils.mkdir_p(run_dir)
        File.open(File.join(run_dir, 'gepa_state.bin'), 'wb') do |file|
          data = instance_variables.each_with_object({}) do |ivar, acc|
            acc[ivar.to_s.delete('@')] = instance_variable_get(ivar)
          end
          Marshal.dump(data, file)
        end
      end

      sig { params(run_dir: String).returns(State) }
      def self.load(run_dir)
        File.open(File.join(run_dir, 'gepa_state.bin'), 'rb') do |file|
          data = Marshal.load(file)
          state = allocate
          data.each { |key, value| state.instance_variable_set("@#{key}", value) }
          state.consistent?
          state
        end
      end

      sig do
        params(
          parent_program_idx: T::Array[Integer],
          new_program: T::Hash[String, String],
          valset_score: Float,
          valset_outputs: T::Array[T.untyped],
          valset_subscores: T::Array[Float],
          run_dir: T.nilable(String),
          num_metric_calls: Integer
        ).returns([Integer, Integer])
      end
      def update_state_with_new_program(
        parent_program_idx,
        new_program,
        valset_score,
        valset_outputs,
        valset_subscores,
        run_dir,
        num_metric_calls
      )
        new_program_idx = @program_candidates.length
        @program_candidates << new_program.dup
        @num_metric_calls_by_discovery << num_metric_calls

        max_predictor_id = parent_program_idx.map { |idx| @named_predictor_id_to_update_next_for_program_candidate[idx] }.compact.max
        @named_predictor_id_to_update_next_for_program_candidate << (max_predictor_id || 0)
        @parent_program_for_candidate << parent_program_idx.dup

        @prog_candidate_val_subscores << valset_subscores.dup
        @program_full_scores_val_set << valset_score.to_f

        valset_subscores.each_with_index do |new_score, task_idx|
          old_score = @pareto_front_valset[task_idx]
          if new_score > old_score
            @pareto_front_valset[task_idx] = new_score
            @program_at_pareto_front_valset[task_idx] = Set.new([new_program_idx])
            if @best_outputs_valset
              @best_outputs_valset[task_idx] = [[new_program_idx, valset_outputs[task_idx]]]
            end
            write_best_output(run_dir, task_idx, new_program_idx, valset_outputs[task_idx])
          elsif new_score == old_score
            @program_at_pareto_front_valset[task_idx].add(new_program_idx)
            if @best_outputs_valset
              @best_outputs_valset[task_idx] << [new_program_idx, valset_outputs[task_idx]]
            end
          end
        end

        raise 'valset subscores length mismatch' unless valset_subscores.length == @program_at_pareto_front_valset.length

        @per_program_tracked_scores = @program_full_scores_val_set.dup
        linear_idx = GEPA::Utils::Pareto.idxmax(@per_program_tracked_scores)

        [new_program_idx, linear_idx]
      end

      sig do
        params(
          eval_output: [T::Array[T.untyped], T::Array[Float]],
          output_dir: String
        ).void
      end
      def self.write_eval_output_to_directory(eval_output, output_dir)
        _, scores = eval_output
        scores.each_with_index do |_score, task_idx|
          dir = File.join(output_dir, "task_#{task_idx}")
          FileUtils.mkdir_p(dir)
          path = File.join(dir, 'iter_0_prog_0.json')
          File.write(path, JSON.pretty_generate(scores[task_idx]))
        end
      end

      sig do
        params(
          run_dir: T.nilable(String),
          logger: T.untyped,
          seed_candidate: T::Hash[String, String],
          valset_evaluator: T.proc.params(arg0: T::Hash[String, String]).returns([T::Array[T.untyped], T::Array[Float]]),
          track_best_outputs: T::Boolean
        ).returns(State)
      end
      def self.initialize_gepa_state(run_dir:, logger:, seed_candidate:, valset_evaluator:, track_best_outputs: false)
        if run_dir && File.exist?(File.join(run_dir, 'gepa_state.bin')) && File.exist?(File.join(run_dir, 'prog_candidates'))
          logger.log('Loading gepa state from run dir')
          return load(run_dir)
        end

        valset_out = valset_evaluator.call(seed_candidate)
        if run_dir
          write_eval_output_to_directory(valset_out, File.join(run_dir, 'generated_best_outputs_valset'))
        end

        state = new(seed_candidate, valset_out, track_best_outputs: track_best_outputs)
        state.num_full_ds_evals = 1
        state.total_num_evals = valset_out.last.length
        state
      end

      private

      sig do
        params(run_dir: T.nilable(String), task_idx: Integer, program_idx: Integer, output: T.untyped).void
      end
      def write_best_output(run_dir, task_idx, program_idx, output)
        return if run_dir.nil?

        dir = File.join(run_dir, 'generated_best_outputs_valset', "task_#{task_idx}")
        FileUtils.mkdir_p(dir)
        payload = ensure_jsonable(output)
        File.write(File.join(dir, "iter_#{@i + 1}_prog_#{program_idx}.json"), JSON.pretty_generate(payload))
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def ensure_jsonable(value)
        JSON.parse(JSON.generate(value))
      rescue StandardError
        GEPA::Utils::Pareto.json_default(value)
      end
    end
  end
end

