# frozen_string_literal: true

require 'sorbet-runtime'

module GEPA
  module Strategies
    class EpochShuffledBatchSampler
      extend T::Sig

      sig { params(minibatch_size: Integer, rng: T.nilable(Random), telemetry: T.nilable(T.untyped)).void }
      def initialize(minibatch_size, rng: nil, telemetry: nil)
        @minibatch_size = minibatch_size
        @rng = rng || Random.new(0)
        @telemetry = telemetry
        @shuffled_ids = []
        @epoch = -1
        @id_freqs = Hash.new(0)
      end

      sig { params(trainset_size: Integer, iteration: Integer).returns(T::Array[Integer]) }
      def next_minibatch_indices(trainset_size, iteration)
        with_span(
          'gepa.strategies.batch_sampler',
          minibatch_size: @minibatch_size,
          trainset_size: trainset_size,
          iteration: iteration
        ) do
          ensure_epoch(trainset_size, iteration)
          base_idx = (iteration * @minibatch_size) % @shuffled_ids.length
          end_idx = base_idx + @minibatch_size
          @shuffled_ids[base_idx...end_idx]
        end
      end

      private

      sig { returns(T.untyped) }
      def telemetry
        @telemetry || GEPA::Telemetry
      end

      sig { params(trainset_size: Integer, iteration: Integer).void }
      def ensure_epoch(trainset_size, iteration)
        update_shuffled(trainset_size) if @shuffled_ids.empty?

        curr_epoch = if @epoch == -1
          0
        else
          (iteration * @minibatch_size) / [@shuffled_ids.length, 1].max
        end

        return unless curr_epoch > @epoch

        @epoch = curr_epoch
        update_shuffled(trainset_size)
      end

      sig { params(trainset_size: Integer).void }
      def update_shuffled(trainset_size)
        @shuffled_ids = Array.new(trainset_size) { |idx| idx }
        @shuffled_ids = @shuffled_ids.shuffle(random: @rng)

        @shuffled_ids.each { |idx| @id_freqs[idx] += 1 }

        remainder = trainset_size % @minibatch_size
        num_to_pad = remainder.zero? ? 0 : (@minibatch_size - remainder)

        num_to_pad.times do
          least_used = @id_freqs.min_by { |_idx, count| count }&.first || 0
          @shuffled_ids << least_used
          @id_freqs[least_used] += 1
        end

        raise ArgumentError, 'minibatch size must be positive' if @minibatch_size <= 0
        raise 'shuffled ids shorter than minibatch size' if @shuffled_ids.length < @minibatch_size
        raise 'shuffled ids not aligned to minibatch size' unless (@shuffled_ids.length % @minibatch_size).zero?
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
