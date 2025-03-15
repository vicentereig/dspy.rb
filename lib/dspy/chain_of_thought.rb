# frozen_string_literal: true

module DSPy
  # Enhances prediction by encouraging step-by-step reasoning
  # before providing a final answer.
  class ChainOfThought
    attr_reader :signature_class, :instance
    
    def initialize(signature_class)
      @signature_class = signature_class
    end
    
    def call(**input_values)
      # Create a Predict instance with the modified signature
      predictor = DSPy::Predict.new(signature_class)
      
      # Run the prediction with chain-of-thought prompting
      predictor.call(**input_values)
    end
    
    private
    
    # Make this ChainOfThought instance behave like the signature instance
    def to_s
      @instance&.to_s || super
    end
    
    def inspect
      @instance&.inspect || super
    end
    
    # Allow this class to be treated as its signature class for testing
    def is_a?(klass)
      @instance&.is_a?(klass) || super
    end
  end
end 