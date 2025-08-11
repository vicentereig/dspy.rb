# frozen_string_literal: true

require 'spec_helper'

# Integration test to verify error formatting works with real prediction failures
RSpec.describe 'Error Formatting Integration' do
  # Define test structs that mirror the real error scenario
  class DrugSymptomPair < T::Struct
    const :drug, String
    const :symptom, String
  end

  class TestSignature < DSPy::Signature
    description "Test signature for error formatting"
    
    input do
      const :query, String, description: "Medical query"
    end
    
    output do
      const :drug_symptom_pairs, T::Array[DrugSymptomPair], description: "Array of drug-symptom pairs"
    end
  end

  context 'when struct instantiation fails with type errors' do
    it 'provides human-readable error message for array type mismatch' do
      # Direct test of what happens when combined_struct.new fails
      predictor = DSPy::Predict.new(TestSignature)
      combined_struct = predictor.send(:create_combined_struct_class)
      
      # This simulates the exact scenario from the user's error
      input_values = { query: "test query" }
      output_attributes = { 
        drug_symptom_pairs: [
          {"_type" => "DrugSymptomPair", "drug" => "medication_x", "symptom" => "chest pain"},
          {"_type" => "DrugSymptomPair", "drug" => "medication_x", "symptom" => "irregular heartbeat"}
        ]
      }
      all_attributes = input_values.merge(output_attributes)
      
      # This should raise the TypeError that gets caught and formatted
      expect {
        combined_struct.new(**all_attributes)
      }.to raise_error(TypeError) do |type_error|
        # Now test how our PredictionInvalidError formats this
        prediction_error = DSPy::PredictionInvalidError.new({ output: type_error.message })
        
        expect(prediction_error.message).to include("Prediction validation failed:")
        expect(prediction_error.message).to include("Type Mismatch in 'drug_symptom_pairs'")
        expect(prediction_error.message).to include("Expected: T::Array[DrugSymptomPair]")
        expect(prediction_error.message).to include("Received: Array (plain Ruby array)")
        expect(prediction_error.message).to include("The LLM returned a plain Ruby array with hash elements")
        expect(prediction_error.message).to include("Suggestions:")
        expect(prediction_error.message).to include("Check your signature uses proper T::Array[DrugSymptomPair] typing")
        
        # Verify original error data is preserved for programmatic access
        expect(prediction_error.errors).to have_key(:output)
        expect(prediction_error.errors[:output]).to be_a(String)
        expect(prediction_error.errors[:output]).to include("Can't set .drug_symptom_pairs")
      end
    end

    it 'handles missing required fields error' do
      predictor = DSPy::Predict.new(TestSignature)
      combined_struct = predictor.send(:create_combined_struct_class)
      
      # Missing the required query field should cause ArgumentError
      expect {
        combined_struct.new(drug_symptom_pairs: [])
      }.to raise_error(ArgumentError) do |arg_error|
        # Test how our PredictionInvalidError formats this
        prediction_error = DSPy::PredictionInvalidError.new({ output: arg_error.message })
        
        expect(prediction_error.message).to include("Prediction validation failed:")
        expect(prediction_error.errors).to have_key(:output)
      end
    end
  end

  context 'integration with existing error handling patterns' do
    it 'works with existing rescue patterns in user code' do
      # Simulate production error handling pattern using direct error creation
      result = nil
      error_caught = nil

      begin
        # Simulate the exact error that would be raised by predict.rb:144-146
        sorbet_error = "Parameter 'items': Can't set .items to [] (instance of Array) - need a T::Array[ItemStruct]\nCaller: /path/to/sorbet"
        raise DSPy::PredictionInvalidError.new({ output: sorbet_error })
      rescue DSPy::PredictionInvalidError => e
        error_caught = e
      end

      expect(result).to be_nil
      expect(error_caught).to be_a(DSPy::PredictionInvalidError)
      expect(error_caught.message).to include("Type Mismatch in 'items'")
      expect(error_caught.errors).to have_key(:output)
    end

    it 'preserves backward compatibility for error.errors access' do
      original_error_message = "Parameter 'field': Can't set .field to value (instance of String) - need a Integer"
      
      begin
        raise DSPy::PredictionInvalidError.new({ output: original_error_message })
      rescue DSPy::PredictionInvalidError => e
        # Verify programmatic access still works
        expect(e.errors[:output]).to eq(original_error_message)
        expect(e.errors[:output]).to be_a(String)
        
        # Verify the message is enhanced for humans
        expect(e.message).to include("Type Mismatch in 'field'")
        expect(e.message).not_to eq("Prediction validation failed: #{e.errors}")
      end
    end

    it 'demonstrates the improvement with the exact user error' do
      # The exact error message from the user's report
      user_error = "Parameter 'drug_symptom_pairs': Can't set .drug_symptom_pairs to " \
                  "[{\"_type\"=>\"DrugSymptomPair\", \"drug\"=>\"medication_x\", \"symptom\"=>\"chest pain\"}, " \
                  "{\"_type\"=>\"DrugSymptomPair\", \"drug\"=>\"medication_x\", \"symptom\"=>\"irregular heartbeat\"}] " \
                  "(instance of Array) - need a T::Array[ADEPredictor::DrugSymptomPair]\nCaller: " \
                  "/Users/vicente/.rbenv/versions/3.3.5/lib/ruby/gems/3.3.0/gems/sorbet-runtime-0.5.12383/lib/types/private/methods/call_validation.rb:282\n"

      error = DSPy::PredictionInvalidError.new({ output: user_error })

      # The new formatted message should be much more readable
      expect(error.message).to include("Type Mismatch in 'drug_symptom_pairs'")
      expect(error.message).to include("Expected: T::Array[ADEPredictor::DrugSymptomPair]")
      expect(error.message).to include("Received: Array (plain Ruby array)")
      expect(error.message).to include("The LLM returned a plain Ruby array with hash elements")
      expect(error.message).to include("Suggestions:")
      expect(error.message).to include("Check your signature uses proper T::Array[ADEPredictor::DrugSymptomPair] typing")
      
      # Should not include the Sorbet stack trace in the formatted message
      expect(error.message).not_to include("Caller:")
      expect(error.message).not_to include("call_validation.rb:282")
      
      # But should preserve the original for programmatic access
      expect(error.errors[:output]).to eq(user_error)
    end
  end
end