# frozen_string_literal: true

module DSPy
  class Predict
    def initialize(signature_class)
      @signature_class = signature_class
    end

    def call(**input_values)
      signature = @signature_class.new
      # validate inputs
      @signature_class.input_schema.call(input_values)
      # build prompt
      # invoke LM
      # validate ouputs
      # return them
    end
  end
end
