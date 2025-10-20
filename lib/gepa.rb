# frozen_string_literal: true

require_relative 'gepa/version'
require_relative 'gepa/telemetry'
require_relative 'gepa/logging'
require_relative 'gepa/utils/pareto'
require_relative 'gepa/strategies/batch_sampler'
require_relative 'gepa/strategies/candidate_selector'
require_relative 'gepa/strategies/component_selector'
require_relative 'gepa/strategies/instruction_proposal'
require_relative 'gepa/core/evaluation_batch'
require_relative 'gepa/core/result'
require_relative 'gepa/core/state'
require_relative 'gepa/core/engine'
require_relative 'gepa/proposer/base'
require_relative 'gepa/proposer/reflective_mutation/base'
require_relative 'gepa/proposer/reflective_mutation/reflective_mutation'
require_relative 'gepa/proposer/merge_proposer'
require_relative 'gepa/api'

module GEPA
end
