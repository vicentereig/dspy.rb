# frozen_string_literal: true

require "sorbet-runtime"
require "exa"

require_relative "deep_search/version"
require_relative "deep_search/token_budget"
require_relative "deep_search/gap_queue"
require_relative "deep_search/clients/exa_client"
require_relative "deep_search/signatures"
require_relative "deep_search/module"

module DSPy
  module DeepSearch
    extend T::Sig
  end
end
