# frozen_string_literal: true

module DSPy
  class Module
    def forward(...)
      raise NotImplementedError, "Subclasses must implement forward method"
    end
    
    def call(...)
      forward(...)
    end
  end
end 