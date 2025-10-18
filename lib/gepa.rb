# frozen_string_literal: true

module GEPA
  autoload :Telemetry, 'gepa/telemetry'

  autoload :API, 'gepa/api'

  module Core
    autoload :EvaluationBatch, 'gepa/core/evaluation_batch'
    autoload :Result, 'gepa/core/result'
    autoload :State, 'gepa/core/state'
    autoload :Engine, 'gepa/core/engine'
  end

  module Strategies
    autoload :RoundRobinReflectionComponentSelector, 'gepa/strategies/component_selector'
    autoload :ParetoCandidateSelector, 'gepa/strategies/candidate_selector'
    autoload :CurrentBestCandidateSelector, 'gepa/strategies/candidate_selector'
    autoload :EpochShuffledBatchSampler, 'gepa/strategies/batch_sampler'
    autoload :InstructionProposalSignature, 'gepa/strategies/instruction_proposal'
  end

  module Utils
    autoload :Pareto, 'gepa/utils/pareto'
  end

  module Proposer
    autoload :CandidateProposal, 'gepa/proposer/base'
    autoload :ProposeNewCandidate, 'gepa/proposer/base'
    autoload :ReflectiveMutationProposer, 'gepa/proposer/reflective_mutation/reflective_mutation'
  end

  autoload :Logging, 'gepa/logging'
end
