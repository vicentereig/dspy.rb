# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Scores
    # Langfuse score data types
    # Maps to: NUMERIC, BOOLEAN, CATEGORICAL
    class DataType < T::Enum
      extend T::Sig

      enums do
        Numeric = new('NUMERIC')
        Boolean = new('BOOLEAN')
        Categorical = new('CATEGORICAL')
      end

      sig { params(value: String).returns(DataType) }
      def self.deserialize(value)
        case value
        when 'NUMERIC' then Numeric
        when 'BOOLEAN' then Boolean
        when 'CATEGORICAL' then Categorical
        else
          raise ArgumentError, "Unknown DataType: #{value}"
        end
      end
    end
  end
end
