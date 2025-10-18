# frozen_string_literal: true

require 'sorbet-runtime'

module GEPA
  module Proposer
    class CandidateProposal < T::Struct
      extend T::Sig

      const :candidate, T::Hash[String, String]
      const :parent_program_ids, T::Array[Integer]
      const :subsample_indices, T.nilable(T::Array[Integer]), default: nil
      const :subsample_scores_before, T.nilable(T::Array[Float]), default: nil
      const :subsample_scores_after, T.nilable(T::Array[Float]), default: nil
      const :tag, String, default: 'reflective_mutation'
      const :metadata, T::Hash[Symbol, T.untyped], default: {}
    end

    module ProposeNewCandidate
      extend T::Sig

      sig { abstract.params(state: GEPA::Core::State).returns(T.nilable(CandidateProposal)) }
      def propose(state); end
    end
  end
end

