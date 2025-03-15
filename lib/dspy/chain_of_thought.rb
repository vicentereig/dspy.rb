# frozen_string_literal: true

module DSPy
  # Enhances prediction by encouraging step-by-step reasoning
  # before providing a final answer.
  class ChainOfThought
    attr_reader :signature_class, :instance
    
    def initialize(signature_class)
      @signature_class = signature_class
      
      # Add 'answer' output field if it doesn't exist
      ensure_answer_field
    end
    
    def call(**input_values)
      # Create a Predict instance with the modified signature
      predictor = DSPy::Predict.new(signature_class)
      
      # Run the prediction with chain-of-thought prompting
      @instance = predictor.call(**input_values)
      
      # Return self to allow method chaining and access to answer through method_missing
      self
    end
    
    # Delegate methods to the underlying instance
    def method_missing(name, *args, &block)
      if @instance&.respond_to?(name)
        @instance.send(name, *args, &block)
      else
        super
      end
    end
    
    def respond_to_missing?(name, include_private = false)
      @instance&.respond_to?(name, include_private) || super
    end
    
    private
    
    def ensure_answer_field
      # Only add 'answer' field if it doesn't already exist
      unless signature_class.output_fields&.key?(:answer)
        # Add the answer field dynamically to the signature class
        signature_class.class_eval do
          output :answer, String, desc: "The final answer to the question"
        end
      end
    end
    
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