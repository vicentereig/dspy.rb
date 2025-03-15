# frozen_string_literal: true

module DSPy
  class Predict
    def initialize(signature_class)
      @signature_class = signature_class
    end
    
    def call(**input_values)
      # Create a new instance of the signature
      signature = @signature_class.new
      
      # Validate that all required inputs are provided
      validate_inputs(input_values)
      
      # Generate a prediction using the configured LM
      DSPy.lm.generate(input_values, signature)
    end
    
    private
    
    def validate_inputs(input_values)
      required_inputs = @signature_class.input_fields.keys
      missing_inputs = required_inputs - input_values.keys
      
      if missing_inputs.any?
        raise ArgumentError, "Missing required inputs: #{missing_inputs.join(', ')}"
      end
    end
  end
end 