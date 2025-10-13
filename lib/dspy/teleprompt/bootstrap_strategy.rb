# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Teleprompt
    # Bootstrap strategy enum for create_n_fewshot_demo_sets
    # Provides type-safe alternatives to Python's magic number seeds
    class BootstrapStrategy < T::Enum
      enums do
        # No demonstrations - zero-shot learning (Python seed = -3)
        ZeroShot = new

        # Labeled examples only - no bootstrap generation (Python seed = -2)
        LabeledOnly = new

        # Bootstrapped demonstrations without shuffling (Python seed = -1)
        Unshuffled = new

        # Bootstrapped demonstrations with shuffling and random size (Python seed >= 0)
        # Requires separate seed parameter for reproducibility
        Shuffled = new
      end
    end
  end
end
