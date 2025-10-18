# frozen_string_literal: true

require 'json'
require 'set'
require 'sorbet-runtime'

module GEPA
  module Utils
    module Pareto
      extend T::Sig

      sig { params(value: T.untyped).returns(T.untyped) }
      def self.json_default(value)
        value.is_a?(Hash) ? value.transform_keys(&:to_s) : JSON.parse(value.to_json)
      rescue StandardError
        { value: value.to_s }
      end

      sig { params(values: T::Array[Float]).returns(Integer) }
      def self.idxmax(values)
        raise ArgumentError, 'values must not be empty' if values.empty?

        values.each_with_index.max_by { |score, _i| score }&.last || 0
      end

      sig do
        params(
          program_at_pareto_front_valset: T::Array[T.untyped],
          scores: T.nilable(T::Hash[Integer, Float])
        ).returns(T::Array[T.untyped])
      end
      def self.remove_dominated_programs(program_at_pareto_front_valset, scores: nil)
        normalized_fronts = program_at_pareto_front_valset.map { |front| front.to_a }

        frequency = Hash.new(0)
        normalized_fronts.each do |front|
          front.each { |program_idx| frequency[program_idx] += 1 }
        end

        all_programs = frequency.keys
        scores ||= all_programs.to_h { |idx| [idx, 1.0] }

        sorted_programs = all_programs.sort_by { |idx| scores.fetch(idx, 0.0) }

        dominated = Set.new
        loop do
          found = false
          sorted_programs.each do |candidate|
            next if dominated.include?(candidate)
            next unless dominated?(candidate, sorted_programs.to_set, dominated, normalized_fronts)

            dominated.add(candidate)
            found = true
            break
          end
          break unless found
        end

        dominators = sorted_programs.reject { |idx| dominated.include?(idx) }
        dominators_set = dominators.to_set

        normalized_fronts.map do |front|
          front.select { |idx| dominators_set.include?(idx) }
        end
      end

      sig do
        params(
          pareto_front_programs: T::Array[T.untyped],
          train_val_weighted_scores: T::Hash[Integer, Float]
        ).returns(T::Array[Integer])
      end
      def self.find_dominator_programs(pareto_front_programs, train_val_weighted_scores)
        cleaned_frontiers = remove_dominated_programs(pareto_front_programs, scores: train_val_weighted_scores)
        cleaned_frontiers.flat_map(&:to_a).uniq
      end

      sig do
        params(
          pareto_front_programs: T::Array[T.untyped],
          weighted_scores: T::Hash[Integer, Float],
          rng: Random
        ).returns(Integer)
      end
      def self.select_program_candidate_from_pareto_front(pareto_front_programs, weighted_scores, rng)
        cleaned_frontiers = remove_dominated_programs(pareto_front_programs, scores: weighted_scores)
        frequency = Hash.new(0)
        cleaned_frontiers.each do |front|
          front.each { |idx| frequency[idx] += 1 }
        end
        raise ArgumentError, 'pareto front is empty' if frequency.empty?

        sampling_list = frequency.flat_map { |idx, freq| [idx] * freq }
        sampling_list[rng.rand(sampling_list.length)]
      end

      class << self
        extend T::Sig
        private

        sig do
          params(
            candidate: Integer,
            program_set: Set,
            dominated: Set,
            pareto_fronts: T::Array[T::Array[Integer]]
          ).returns(T::Boolean)
        end
        def dominated?(candidate, program_set, dominated, pareto_fronts)
          candidate_fronts = pareto_fronts.select { |front| front.include?(candidate) }
          candidate_fronts.all? do |front|
            remaining = front.reject { |idx| idx == candidate || dominated.include?(idx) }
            remaining.any? { |other| program_set.include?(other) }
          end
        end
      end
    end
  end
end
