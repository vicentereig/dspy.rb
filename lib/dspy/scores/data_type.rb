# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Scores
    # Langfuse score data types
    # Maps to: NUMERIC, BOOLEAN, CATEGORICAL
    class DataType < T::Enum
      enums do
        Numeric = new('NUMERIC')
        Boolean = new('BOOLEAN')
        Categorical = new('CATEGORICAL')
      end
    end
  end
end
