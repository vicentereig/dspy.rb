# frozen_string_literal: true

module GEPA
  module Logging
    autoload :Logger, 'gepa/logging/logger'
    autoload :CompositeLogger, 'gepa/logging/logger'
    autoload :BufferingLogger, 'gepa/logging/logger'
    autoload :ExperimentTracker, 'gepa/logging/experiment_tracker'
  end
end
