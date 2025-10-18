# frozen_string_literal: true

module GEPA
  autoload :Telemetry, 'gepa/telemetry'

  module Core
    autoload :EvaluationBatch, 'gepa/core/evaluation_batch'
    autoload :Result, 'gepa/core/result'
    autoload :State, 'gepa/core/state'
  end

  module Utils
    autoload :Pareto, 'gepa/utils/pareto'
  end
end
