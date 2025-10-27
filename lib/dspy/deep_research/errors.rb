# frozen_string_literal: true

module DSPy
  module DeepResearch
    class Error < DSPy::Error; end
    class EvidenceDeficitError < Error; end
    class QueueStarvationError < Error; end
    class SynthesisCoherenceError < Error; end
  end
end
