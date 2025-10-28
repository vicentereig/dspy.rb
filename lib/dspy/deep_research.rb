# frozen_string_literal: true

require "sorbet-runtime"

require_relative "deep_search"

require_relative "deep_research/version"
require_relative "deep_research/errors"
require_relative "deep_research/signatures"
require_relative "deep_research/section_queue"
require_relative "deep_research/module"
require_relative "deep_research_with_memory"

module DSPy
  module DeepResearch
    extend T::Sig
  end
end
