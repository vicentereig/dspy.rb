# frozen_string_literal: true

require 'sorbet-runtime'

module GEPA
  module Core
    # Container for evaluating a candidate on a batch.
    class EvaluationBatch < T::Struct
      const :outputs, T::Array[T.untyped]
      const :scores, T::Array[Float]
      const :trajectories, T.nilable(T::Array[T.untyped])

      sig { void }
      def initialize(*)
        super
        raise ArgumentError, 'outputs and scores length mismatch' unless outputs.length == scores.length

        if trajectories
          raise ArgumentError, 'trajectories length mismatch' unless trajectories.length == outputs.length
        end
      end
    end
  end
end

