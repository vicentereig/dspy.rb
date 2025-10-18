# frozen_string_literal: true

require 'sorbet-runtime'

require_relative '../base'
require_relative 'base'

module GEPA
  module Proposer
    class ReflectiveMutationProposer
      extend T::Sig
      include ProposeNewCandidate

      sig do
        params(
          logger: T.untyped,
          trainset: T::Array[T.untyped],
          adapter: T.untyped,
          candidate_selector: T.untyped,
          module_selector: T.untyped,
          batch_sampler: T.untyped,
          perfect_score: Float,
          skip_perfect_score: T::Boolean,
          experiment_tracker: T.untyped,
          reflection_lm: T.nilable(T.proc.params(prompt: String).returns(String)),
          telemetry: T.nilable(T.untyped)
        ).void
      end
      def initialize(
        logger:,
        trainset:,
        adapter:,
        candidate_selector:,
        module_selector:,
        batch_sampler:,
        perfect_score:,
        skip_perfect_score:,
        experiment_tracker:,
        reflection_lm: nil,
        telemetry: nil
      )
        @logger = logger
        @trainset = trainset
        @adapter = adapter
        @candidate_selector = candidate_selector
        @module_selector = module_selector
        @batch_sampler = batch_sampler
        @perfect_score = perfect_score
        @skip_perfect_score = skip_perfect_score
        @experiment_tracker = experiment_tracker
        @reflection_lm = reflection_lm
        @telemetry = telemetry || GEPA::Telemetry
      end

      sig { override.params(state: GEPA::Core::State).returns(T.nilable(CandidateProposal)) }
      def propose(state)
        iteration = state.i + 1

        with_span('gepa.proposer.reflective_mutation.propose', iteration: iteration) do
          proposal_for_iteration(state, iteration)
        end
      end

      private

      def proposal_for_iteration(state, iteration)
        curr_prog_id = @candidate_selector.select_candidate_idx(state)
        curr_prog = state.program_candidates[curr_prog_id]
        ensure_trace_slot(state)
        state.full_program_trace.last[:selected_program_candidate] = curr_prog_id

        @logger.log("Iteration #{iteration}: Selected program #{curr_prog_id} score: #{state.per_program_tracked_scores[curr_prog_id]}")
        @experiment_tracker.log_metrics({ iteration: iteration, selected_program_candidate: curr_prog_id }, step: iteration)

        subsample_ids = @batch_sampler.next_minibatch_indices(@trainset.length, iteration - 1)
        state.full_program_trace.last[:subsample_ids] = subsample_ids
        minibatch = subsample_ids.map { |idx| @trainset[idx] }

        eval_curr = with_span('gepa.proposer.evaluate_current', iteration: iteration) do
          @adapter.evaluate(minibatch, curr_prog, capture_traces: true)
        end

        unless eval_curr.trajectories && !eval_curr.trajectories.empty?
          @logger.log("Iteration #{iteration}: No trajectories captured. Skipping.")
          return nil
        end

        state.total_num_evals += subsample_ids.length
        state.full_program_trace.last[:subsample_scores] = eval_curr.scores

        if @skip_perfect_score && eval_curr.scores.all? { |score| score >= @perfect_score }
          @logger.log("Iteration #{iteration}: All subsample scores perfect. Skipping.")
          return nil
        end

        @experiment_tracker.log_metrics({ subsample_score: eval_curr.scores.sum }, step: iteration)

        predictor_names = @module_selector.select_modules(
          state,
          eval_curr.trajectories,
          eval_curr.scores,
          curr_prog_id,
          curr_prog
        )

        reflective_dataset = nil
        new_texts = nil

        with_span('gepa.proposer.build_reflective_dataset', iteration: iteration) do
          reflective_dataset = @adapter.make_reflective_dataset(curr_prog, eval_curr, predictor_names)
        end

        begin
          new_texts = with_span('gepa.proposer.propose_texts', iteration: iteration) do
            propose_new_texts(curr_prog, reflective_dataset, predictor_names)
          end

          new_texts.each do |name, text|
            @logger.log("Iteration #{iteration}: Proposed new text for #{name}: #{text}")
          end
          @experiment_tracker.log_metrics(new_texts.transform_keys { |name| "new_instruction_#{name}" }, step: iteration)
        rescue StandardError => e
          @logger.log("Iteration #{iteration}: Exception during reflection/proposal: #{e}")
          @logger.log(e.backtrace&.join("\n"))
          return nil
        end

        new_candidate = curr_prog.dup
        new_texts.each do |name, text|
          raise ArgumentError, "Missing component #{name}" unless new_candidate.key?(name)
          new_candidate[name] = text
        end

        eval_new = with_span('gepa.proposer.evaluate_new_candidate', iteration: iteration) do
          @adapter.evaluate(minibatch, new_candidate, capture_traces: false)
        end

        state.total_num_evals += subsample_ids.length
        state.full_program_trace.last[:new_subsample_scores] = eval_new.scores
        @experiment_tracker.log_metrics({ new_subsample_score: eval_new.scores.sum }, step: iteration)

        CandidateProposal.new(
          candidate: new_candidate,
          parent_program_ids: [curr_prog_id],
          subsample_indices: subsample_ids,
          subsample_scores_before: eval_curr.scores,
          subsample_scores_after: eval_new.scores,
          metadata: { iteration: iteration }
        )
      end

      sig do
        params(
          candidate: T::Hash[String, String],
          reflective_dataset: T::Hash[String, T::Array[T::Hash[String, T.untyped]]],
          components_to_update: T::Array[String]
        ).returns(T::Hash[String, String])
      end
      def propose_new_texts(candidate, reflective_dataset, components_to_update)
        if @adapter.respond_to?(:propose_new_texts) && @adapter.propose_new_texts
          return @adapter.propose_new_texts(candidate, reflective_dataset, components_to_update)
        end

        raise ArgumentError, 'reflection_lm is required when adapter lacks propose_new_texts' unless @reflection_lm

        components_to_update.each_with_object({}) do |name, acc|
          signature_input = {
            'current_instruction_doc' => candidate[name],
            'dataset_with_feedback' => reflective_dataset.fetch(name)
          }
          acc[name] = GEPA::Strategies::InstructionProposalSignature.run(@reflection_lm, signature_input)['new_instruction']
        end
      end

      sig { params(state: GEPA::Core::State).void }
      def ensure_trace_slot(state)
        state.full_program_trace << {} if state.full_program_trace.empty? || state.full_program_trace.last.nil?
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

