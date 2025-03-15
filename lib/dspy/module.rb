# frozen_string_literal: true

module DSPy
  class Module
    def forward(...)
      raise NotImplementedError, "Subclasses must implement forward method"
    end
    
    def call(...)
      forward(...)
    end
    
    # Allow creating predictions with multiple fields
    def prediction(**kwargs)
      Prediction.new(**kwargs)
    end
  end
  
  # Simple class to hold prediction results
  class Prediction
    def initialize(**kwargs)
      kwargs.each do |key, value|
        instance_variable_set(:"@#{key}", value)
        
        # Define getter method for this attribute
        self.class.class_eval do
          define_method(key) { instance_variable_get(:"@#{key}") }
        end
      end
    end
    
    def to_h
      instance_variables.each_with_object({}) do |var, hash|
        key = var.to_s.delete('@').to_sym
        hash[key] = instance_variable_get(var)
      end
    end
  end
end 