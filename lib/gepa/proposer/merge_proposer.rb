# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'

require_relative 'base'
require_relative '../utils/pareto'
require_relative '../telemetry'

module GEPA
  module Proposer
    # Port of the Python GEPA merge proposer. It fuses two descendants that share
    # a common ancestor by recombining their component instructions and then
    # evaluates the merged program on a Pareto-informed subsample.
    class MergeProposer
      extend T::Sig
      include ProposeNewCandidate

      CandidateTriplet = T.type_alias { [Integer, Integer, Integer] }
      MergeAttempt = T.type_alias { [Integer, Integer, T::Array[Integer]] }

      sig do
        params(
          logger: T.untyped,
          valset: T::Array[T.untyped],
          evaluator: T.proc.params(dataset: T::Array[T.untyped], candidate: T::Hash[String, String])
                          .returns([T::Array[T.untyped], T::Array[Float]]),
          use_merge: T::Boolean,
          max_merge_invocations: Integer,
          rng: T.nilable(Random),
          telemetry: T.nilable(T.untyped)
        ).void
      end
      def initialize(logger:, valset:, evaluator:, use_merge:, max_merge_invocations:, rng: nil, telemetry: nil)
        @logger = logger
        @valset = valset
        @evaluator = evaluator
        @use_merge = use_merge
        @max_merge_invocations = max_merge_invocations
        @rng = rng || Random.new(0)
        @telemetry = telemetry || GEPA::Telemetry

        @merges_due = 0
        @total_merges_tested = 0
        @last_iter_found_new_program = false
        @merges_performed = [[], []]
      end

      sig { returns(Integer) }
      attr_accessor :merges_due

      sig { returns(Integer) }
      attr_accessor :total_merges_tested

      sig { returns(T::Boolean) }
      attr_accessor :last_iter_found_new_program

      sig { returns(Integer) }
      attr_reader :max_merge_invocations

      sig { returns(T::Boolean) }
      attr_reader :use_merge

      sig { void }
      def schedule_if_needed
        return unless @use_merge
        return unless @total_merges_tested < @max_merge_invocations

        @merges_due += 1
      end

      sig do
        params(
          scores1: T::Array[Float],
          scores2: T::Array[Float],
          num_subsample_ids: Integer
        ).returns(T::Array[Integer])
      end
      def select_eval_subsample_for_merged_program(scores1, scores2, num_subsample_ids: 5)
        all_indices = (0...[scores1.length, scores2.length].min).to_a
        p1 = []
        p2 = []
        p3 = []

        all_indices.each do |index|
          s1 = scores1[index]
          s2 = scores2[index]
          if s1 > s2
            p1 << index
          elsif s2 > s1
            p2 << index
          else
            p3 << index
          end
        end

        n_each = (num_subsample_ids / 3.0).ceil
        selected = []
        selected.concat(sample_from(p1, [n_each, p1.length].min))
        selected.concat(sample_from(p2, [n_each, p2.length].min))

        remaining_slots = num_subsample_ids - selected.length
        selected.concat(sample_from(p3, [remaining_slots, p3.length].min))

        remaining_slots = num_subsample_ids - selected.length
        unused = all_indices - selected
        if remaining_slots.positive?
          if unused.length >= remaining_slots
            selected.concat(sample_from(unused, remaining_slots))
          else
            selected.concat(sample_with_replacement(all_indices, remaining_slots))
          end
        end

        selected.take(num_subsample_ids)
      end

      sig { override.params(state: GEPA::Core::State).returns(T.nilable(CandidateProposal)) }
      def propose(state)
        iteration = state.i + 1
        ensure_trace_slot(state)
        state.full_program_trace.last[:invoked_merge] = true

        unless eligible_for_proposal?
          @logger.log("Iteration #{iteration}: No merge candidates scheduled")
          return nil
        end

        merge_candidates = GEPA::Utils::Pareto.find_dominator_programs(
          state.program_at_pareto_front_valset,
          state.per_program_tracked_scores.each_with_index.to_h { |score, idx| [idx, score] }
        )

        success, new_program, id1, id2, ancestor = sample_and_attempt_merge_programs_by_common_predictors(
          state,
          merge_candidates
        )

        unless success
          @logger.log("Iteration #{iteration}: No merge candidates found")
          return nil
        end

        state.full_program_trace.last[:merged] = true
        state.full_program_trace.last[:merged_entities] = [id1, id2, ancestor]
        @merges_performed[0] << [id1, id2, ancestor]

        @logger.log("Iteration #{iteration}: Merged programs #{id1} and #{id2} via ancestor #{ancestor}")

        subsample_ids = select_eval_subsample_for_merged_program(
          state.prog_candidate_val_subscores[id1],
          state.prog_candidate_val_subscores[id2]
        )

        mini_valset = subsample_ids.map { |idx| @valset[idx] }
        id1_sub_scores = subsample_ids.map { |idx| state.prog_candidate_val_subscores[id1][idx] }
        id2_sub_scores = subsample_ids.map { |idx| state.prog_candidate_val_subscores[id2][idx] }

        state.full_program_trace.last[:subsample_ids] = subsample_ids
        state.full_program_trace.last[:id1_subsample_scores] = id1_sub_scores
        state.full_program_trace.last[:id2_subsample_scores] = id2_sub_scores

        _, new_sub_scores = @evaluator.call(mini_valset, new_program)
        state.full_program_trace.last[:new_program_subsample_scores] = new_sub_scores

        state.total_num_evals += subsample_ids.length

        CandidateProposal.new(
          candidate: new_program,
          parent_program_ids: [id1, id2],
          subsample_indices: subsample_ids,
          subsample_scores_before: [id1_sub_scores.sum, id2_sub_scores.sum],
          subsample_scores_after: new_sub_scores,
          tag: 'merge',
          metadata: { ancestor: ancestor }
        )
      end

      private

      attr_reader :logger

      sig { returns(T::Boolean) }
      def eligible_for_proposal?
        @use_merge && @last_iter_found_new_program && @merges_due.positive?
      end

      sig do
        params(state: GEPA::Core::State, merge_candidates: T::Array[Integer])
          .returns([T::Boolean, T.nilable(T::Hash[String, String]), T.nilable(Integer), T.nilable(Integer), T.nilable(Integer)])
      end
      def sample_and_attempt_merge_programs_by_common_predictors(state, merge_candidates)
        return [false, nil, nil, nil, nil] if merge_candidates.length < 2
        return [false, nil, nil, nil, nil] if state.parent_program_for_candidate.length < 3

        10.times do
          ids_to_merge = find_common_ancestor_pair(
            state.parent_program_for_candidate,
            merge_candidates,
            state.per_program_tracked_scores,
            state.program_candidates
          )
          next unless ids_to_merge

          id1, id2, ancestor = ids_to_merge
          return [false, nil, nil, nil, nil] unless id1 && id2 && ancestor

          new_program, new_prog_desc = build_merged_program(
            state.program_candidates,
            id1,
            id2,
            ancestor,
            state.per_program_tracked_scores
          )

          next unless new_program

          if @merges_performed[1].include?([id1, id2, new_prog_desc])
            next
          end

          @merges_performed[1] << [id1, id2, new_prog_desc]
          return [true, new_program, id1, id2, ancestor]
        end

        [false, nil, nil, nil, nil]
      end

      sig do
        params(
          parent_list: T::Array[T::Array[T.nilable(Integer)]],
          merge_candidates: T::Array[Integer],
          agg_scores: T::Array[Float],
          program_candidates: T::Array[T::Hash[String, String]]
        ).returns(T.nilable(CandidateTriplet))
      end
      def find_common_ancestor_pair(parent_list, merge_candidates, agg_scores, program_candidates)
        10.times do
          return nil if merge_candidates.length < 2

          id1, id2 = sample_distinct_pair(merge_candidates)
          next unless id1 && id2

          ancestors_i = collect_ancestors(parent_list, id1)
          ancestors_j = collect_ancestors(parent_list, id2)

          next if ancestors_i.include?(id2) || ancestors_j.include?(id1)

          common = ancestors_i & ancestors_j
          filtered = filter_ancestors(
            id1,
            id2,
            common,
            agg_scores,
            program_candidates
          )
          next if filtered.empty?

          weights = filtered.map { |ancestor| agg_scores[ancestor] }
          ancestor = sample_with_weights(filtered, weights)
          return [id1, id2, ancestor]
        end

        nil
      end

      sig do
        params(
          id1: Integer,
          id2: Integer,
          common_ancestors: T::Array[Integer],
          agg_scores: T::Array[Float],
          program_candidates: T::Array[T::Hash[String, String]]
        ).returns(T::Array[Integer])
      end
      def filter_ancestors(id1, id2, common_ancestors, agg_scores, program_candidates)
        common_ancestors.each_with_object([]) do |ancestor, memo|
          next if @merges_performed[0].include?([id1, id2, ancestor])
          next if agg_scores[ancestor] > agg_scores[id1] || agg_scores[ancestor] > agg_scores[id2]
          next unless desirable_predictors_triplet?(program_candidates, ancestor, id1, id2)

          memo << ancestor
        end
      end

      sig do
        params(
          program_candidates: T::Array[T::Hash[String, String]],
          ancestor: Integer,
          id1: Integer,
          id2: Integer
        ).returns(T::Boolean)
      end
      def desirable_predictors_triplet?(program_candidates, ancestor, id1, id2)
        ancestor_program = program_candidates[ancestor]
        id1_program = program_candidates[id1]
        id2_program = program_candidates[id2]

        ancestor_program.keys.any? do |pred_name|
          pred_anc = ancestor_program[pred_name]
          pred_id1 = id1_program[pred_name]
          pred_id2 = id2_program[pred_name]

          ((pred_anc == pred_id1) || (pred_anc == pred_id2)) &&
            pred_id1 != pred_id2
        end
      end

      sig do
        params(
          program_candidates: T::Array[T::Hash[String, String]],
          id1: Integer,
          id2: Integer,
          ancestor: Integer,
          agg_scores: T::Array[Float]
        ).returns([T.nilable(T::Hash[String, String]), T::Array[Integer]])
      end
      def build_merged_program(program_candidates, id1, id2, ancestor, agg_scores)
        ancestor_program = program_candidates[ancestor]
        id1_program = program_candidates[id1]
        id2_program = program_candidates[id2]

        new_program = ancestor_program.dup
        descriptors = []

        ancestor_program.each_key do |pred_name|
          pred_anc = ancestor_program[pred_name]
          pred_id1 = id1_program[pred_name]
          pred_id2 = id2_program[pred_name]

          if ((pred_anc == pred_id1) || (pred_anc == pred_id2)) && pred_id1 != pred_id2
            replacement_idx = pred_anc == pred_id1 ? id2 : id1
            new_program[pred_name] = program_candidates[replacement_idx][pred_name]
            descriptors << replacement_idx
          elsif pred_anc != pred_id1 && pred_anc != pred_id2
            chosen_idx = if agg_scores[id1] > agg_scores[id2]
              id1
            elsif agg_scores[id2] > agg_scores[id1]
              id2
            else
              @rng.rand(2).zero? ? id1 : id2
            end
            new_program[pred_name] = program_candidates[chosen_idx][pred_name]
            descriptors << chosen_idx
          elsif pred_id1 == pred_id2
            new_program[pred_name] = pred_id1
            descriptors << id1
          else
            raise 'Unexpected predictor merge case'
          end
        end

        [new_program, descriptors]
      end

      sig { params(state: GEPA::Core::State).void }
      def ensure_trace_slot(state)
        state.full_program_trace << {} if state.full_program_trace.empty? || state.full_program_trace.last.nil?
      end

      sig { params(array: T::Array[Integer], count: Integer).returns(T::Array[Integer]) }
      def sample_from(array, count)
        return [] if count <= 0 || array.empty?

        if array.length >= count
          array.sample(count, random: @rng)
        else
          array.dup
        end
      end

      sig { params(array: T::Array[Integer], count: Integer).returns(T::Array[Integer]) }
      def sample_with_replacement(array, count)
        count.times.map { array[@rng.rand(array.length)] }
      end

      sig { params(options: T::Array[Integer], weights: T::Array[Float]).returns(Integer) }
      def sample_with_weights(options, weights)
        total = weights.sum
        return options.first if total.zero?

        pick = @rng.rand * total
        accumulator = 0.0
        options.zip(weights).each do |option, weight|
          accumulator += weight
          return option if pick <= accumulator
        end
        options.last
      end

      sig { params(parent_list: T::Array[T::Array[T.nilable(Integer)]], node: Integer).returns(T::Array[Integer]) }
      def collect_ancestors(parent_list, node)
        visited = Set.new
        traverse_ancestors(parent_list, node, visited)
        visited.to_a
      end

      sig { params(parent_list: T::Array[T::Array[T.nilable(Integer)]], node: Integer, visited: Set).void }
      def traverse_ancestors(parent_list, node, visited)
        parent_list[node].each do |parent|
          next if parent.nil? || visited.include?(parent)

          visited.add(parent)
          traverse_ancestors(parent_list, parent, visited)
        end
      end

      sig { params(candidates: T::Array[Integer]).returns([T.nilable(Integer), T.nilable(Integer)]) }
      def sample_distinct_pair(candidates)
        return [nil, nil] if candidates.length < 2

        first = candidates[@rng.rand(candidates.length)]
        second = candidates[@rng.rand(candidates.length)]
        second = candidates[@rng.rand(candidates.length)] while second == first && candidates.length > 1

        if first && second && second < first
          [second, first]
        else
          [first, second]
        end
      end
    end
  end
end
