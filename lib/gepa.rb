# frozen_string_literal: true

module GEPA
  autoload :Telemetry, 'gepa/telemetry'

  module Core
    autoload :EvaluationBatch, 'gepa/core/evaluation_batch'
    autoload :Result, 'gepa/core/result'
    autoload :State, 'gepa/core/state'
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
end
