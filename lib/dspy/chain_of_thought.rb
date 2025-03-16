# frozen_string_literal: true

module DSPy
  # Enhances prediction by encouraging step-by-step reasoning
  # before providing a final answer.
  class ChainOfThought
    attr_reader :signature_class, :instance

    def initialize(signature_class)
      @signature_class = signature_class

      prompt_with_reasoning = <<~PROMPT
      Reasoning: Let's think step by step in order to #{@signature_class.description}
      
      PROMPT

      @signature_class.class_eval do
        output :reasoning, String, desc: prompt_with_reasoning
      end
    end

    def call(**input_values)
      predictor = DSPy::Predict.new(signature_class)

      predictor.call(**input_values)
    end
  end
end
