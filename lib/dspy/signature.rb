# frozen_string_literal: true

module DSPy
  class Signature
    class << self
      attr_reader :input_schema, :output_schema

      def description(text = nil)
        if text
          @description = text
        else
          @description
        end
      end

      def input(&)
        @input_schema= Dry::Schema::JSON(&)
      end

      def output(&)
        @output_schema = Dry::Schema::JSON(&)
      end
    end
  end
end
