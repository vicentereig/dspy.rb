# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::PredictionInvalidError do
  describe '#initialize' do
    context 'with output validation errors' do
      it 'formats Sorbet type validation errors' do
        sorbet_error = "Parameter 'items': Can't set .items to " \
                      "[{\"name\"=>\"item1\"}] (instance of Array) - need a T::Array[ItemStruct]"
        
        error = described_class.new({ output: sorbet_error })

        expect(error.message).to include("Prediction validation failed:")
        expect(error.message).to include("Type Mismatch in 'items'")
        expect(error.message).to include("Expected: T::Array[ItemStruct]")
        expect(error.message).to include("Received: Array (plain Ruby array)")
        expect(error.message).to include("Suggestions:")
        
        # Verify original error data is preserved
        expect(error.errors).to eq({ output: sorbet_error })
      end

      it 'handles non-string output errors' do
        error_hash = { field: "some error", code: 123 }
        error = described_class.new({ output: error_hash })

        expect(error.message).to include("Prediction validation failed:")
        expect(error.message).to include("output")
        expect(error.message).to include("some error")
        expect(error.message).to include("123")
        expect(error.errors).to eq({ output: error_hash })
      end
    end

    context 'with input validation errors' do
      it 'formats input validation errors' do
        input_error = "missing keyword: name, age"
        
        error = described_class.new({ input: input_error })

        expect(error.message).to include("Input validation failed:")
        expect(error.message).to include("Missing Required Fields")
        expect(error.message).to include("• name")
        expect(error.message).to include("• age")
        
        # Verify original error data is preserved
        expect(error.errors).to eq({ input: input_error })
      end
    end

    context 'with complex error structures' do
      it 'falls back to original format for unrecognized structures' do
        complex_errors = { 
          validation: "failed", 
          details: { field1: "error1", field2: "error2" } 
        }
        
        error = described_class.new(complex_errors)

        expect(error.message).to eq("Prediction validation failed: #{complex_errors}")
        expect(error.errors).to eq(complex_errors)
      end
    end

    context 'with context parameter' do
      it 'stores the context' do
        error = described_class.new({ output: "some error" }, context: "test_context")
        
        expect(error.context).to eq("test_context")
      end

      it 'handles nil context' do
        error = described_class.new({ output: "some error" })
        
        expect(error.context).to be_nil
      end
    end

    context 'backward compatibility' do
      it 'maintains original interface when called with just errors hash' do
        errors = { output: "simple error message" }
        error = described_class.new(errors)

        expect(error.errors).to eq(errors)
        expect(error.context).to be_nil
        expect(error.message).to be_a(String)
      end

      it 'preserves errors hash structure for programmatic access' do
        original_errors = { 
          output: "type error", 
          input: "missing field",
          metadata: { timestamp: Time.now } 
        }
        
        error = described_class.new(original_errors)

        expect(error.errors).to eq(original_errors)
        # Verify the hash wasn't modified during formatting
        expect(error.errors.object_id).to eq(original_errors.object_id)
      end
    end
  end

  describe 'rescue behavior' do
    it 'can be caught as StandardError' do
      expect {
        raise described_class.new({ output: "test error" })
      }.to raise_error(StandardError)
    end

    it 'can be caught specifically as PredictionInvalidError' do
      expect {
        raise described_class.new({ output: "test error" })
      }.to raise_error(described_class)
    end

    it 'preserves error details in rescue blocks' do
      original_errors = { output: "type mismatch" }
      
      begin
        raise described_class.new(original_errors)
      rescue described_class => e
        expect(e.errors).to eq(original_errors)
        expect(e.message).to include("Prediction validation failed")
      end
    end
  end
end
