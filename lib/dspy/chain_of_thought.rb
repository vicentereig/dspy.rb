# frozen_string_literal: true

module DSPy
  # Enhances prediction by encouraging step-by-step reasoning
  # before providing a final answer.
  class ChainOfThought < Predict

    def initialize(signature_class)
      @signature_class = signature_class
      chain_of_thought_schema = Dry::Schema.JSON do
        required(:reasoning).value(:string).meta(description: "Reasoning: Let's think step by step in order to #{signature_class.description}")
      end
      @signature_class.output_schema = Dry::Schema.JSON(parent: [@signature_class.output_schema, chain_of_thought_schema])
    end
  end
end
