# frozen_string_literal: true

require 'spec_helper'

# Shared test modules for GEPA unit tests
# These replace the convoluted mocking approach with proper DSPy::Module classes

class SimpleTestSignature < DSPy::Signature
  description "Simple test signature for GEPA unit tests"

  input do
    const :question, String, description: "A question to answer"
  end
  
  output do
    const :answer, String, description: "The answer"
  end
end

class SimpleTestModule < DSPy::Module
  attr_reader :signature_class
  
  def initialize(signature_class = SimpleTestSignature)
    super()
    @signature_class = signature_class
    @predict = DSPy::Predict.new(signature_class)
  end
  
  def call(**inputs)
    @predict.call(**inputs)
  end
  
  # For GEPA compatibility - programs need to be callable with keyword args
  def forward(**inputs)
    call(**inputs)
  end
end

# Test module with configurable behavior for deterministic unit testing
class MockableTestModule < DSPy::Module
  attr_reader :signature_class
  attr_accessor :mock_response
  
  def initialize(signature_class = SimpleTestSignature)
    super()
    @signature_class = signature_class
    @mock_response = nil
  end
  
  def call(**inputs)
    if @mock_response
      # Return configured mock response
      DSPy::Prediction.new(
        signature_class: @signature_class,
        **@mock_response
      )
    else
      # Fall back to actual DSPy prediction (requires API key)
      DSPy::Predict.new(@signature_class).call(**inputs)
    end
  end
  
  def forward(**inputs)
    call(**inputs)
  end
end

# Math-specific test signature for more realistic testing
class MathTestSignature < DSPy::Signature
  description "Solve math problems step by step"

  input do
    const :problem, String, description: "A math problem to solve"
  end
  
  output do
    const :answer, String, description: "The numerical answer"
    const :reasoning, String, description: "Step-by-step solution"
  end
end

class MathTestModule < DSPy::Module
  attr_reader :signature_class
  
  def initialize
    super()
    @signature_class = MathTestSignature
    @predict = DSPy::Predict.new(MathTestSignature)
  end
  
  def call(problem:)
    @predict.call(problem: problem)
  end
  
  def forward(problem:)
    call(problem: problem)
  end
end