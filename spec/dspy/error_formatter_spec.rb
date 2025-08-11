# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::ErrorFormatter do
  describe '.format_error' do
    context 'when formatting Sorbet type validation errors' do
      it 'formats array type mismatch errors' do
        error_message = "Parameter 'drug_symptom_pairs': Can't set .drug_symptom_pairs to " \
                       "[{\"_type\"=>\"DrugSymptomPair\", \"drug\"=>\"medication_x\", \"symptom\"=>\"chest pain\"}, " \
                       "{\"_type\"=>\"DrugSymptomPair\", \"drug\"=>\"medication_x\", \"symptom\"=>\"irregular heartbeat\"}] " \
                       "(instance of Array) - need a T::Array[ADEPredictor::DrugSymptomPair]\nCaller: /path/to/sorbet"

        result = described_class.format_error(error_message)

        expect(result).to include("Type Mismatch in 'drug_symptom_pairs'")
        expect(result).to include("Expected: T::Array[ADEPredictor::DrugSymptomPair]")
        expect(result).to include("Received: Array (plain Ruby array)")
        expect(result).to include("The LLM returned a plain Ruby array with hash elements")
        expect(result).to include("Check your signature uses proper T::Array[ADEPredictor::DrugSymptomPair] typing")
        expect(result).to include("Sample data received:")
        # Should not include the caller stack trace
        expect(result).not_to include("Caller:")
        expect(result).not_to include("/path/to/sorbet")
      end

      it 'formats struct type mismatch errors' do
        error_message = "Parameter 'address': Can't set .address to " \
                       "{\"street\"=>\"123 Main St\", \"city\"=>\"Boston\"} " \
                       "(instance of Hash) - need a PersonAddress"

        result = described_class.format_error(error_message)

        expect(result).to include("Type Mismatch in 'address'")
        expect(result).to include("Expected: PersonAddress")
        expect(result).to include("Received: Hash (plain Ruby hash)")
        expect(result).to include("The LLM returned a plain Ruby hash, but your signature requires a PersonAddress struct object")
      end

      it 'formats enum type mismatch errors' do
        error_message = "Parameter 'priority': Can't set .priority to " \
                       "\"high\" (instance of String) - need a T::Enum"

        result = described_class.format_error(error_message)

        expect(result).to include("Type Mismatch in 'priority'")
        expect(result).to include("Expected: T::Enum")
        expect(result).to include("Received: String (plain Ruby string)")
        expect(result).to include("The LLM returned a string, but your signature requires an enum value")
      end

      it 'truncates long sample data' do
        long_data = "x" * 150
        error_message = "Parameter 'data': Can't set .data to #{long_data} (instance of String) - need a DataStruct"

        result = described_class.format_error(error_message)

        expect(result).to include("Sample data received: #{"x" * 101}...")
        # The formatted result should truncate the sample data even if overall message is longer
        expect(result).not_to include("x" * 150)  # Verify truncation happened
      end
    end

    context 'when formatting ArgumentError messages' do
      it 'formats missing keyword errors' do
        error_message = "missing keyword: name, age"

        result = described_class.format_error(error_message)

        expect(result).to include("Missing Required Fields")
        expect(result).to include("• name")
        expect(result).to include("• age")
        expect(result).to include("Check your signature definition - these fields should be marked as optional")
        expect(result).to include("This usually happens when the LLM response doesn't include all expected fields")
      end

      it 'formats unknown keyword errors' do
        error_message = "unknown keyword: extra_field, another_field"

        result = described_class.format_error(error_message)

        expect(result).to include("Unknown Fields in Response")
        expect(result).to include("• extra_field")
        expect(result).to include("• another_field")
        expect(result).to include("Check if these fields should be added to your signature definition")
        expect(result).to include("Consider if the LLM is hallucinating extra information")
      end
    end

    context 'when formatting unrecognized error patterns' do
      it 'cleans up the message and removes stack traces' do
        error_message = "Some custom error message\nCaller: /path/to/file.rb:123"

        result = described_class.format_error(error_message)

        expect(result).to eq("Some custom error message")
        expect(result).not_to include("Caller:")
      end

      it 'handles errors with multiple newlines' do
        error_message = "Error message\n\n\nWith extra newlines\n\n"

        result = described_class.format_error(error_message)

        expect(result).to eq("Error message\nWith extra newlines")
      end
    end
  end

  describe 'private methods' do
    describe '.sorbet_type_error?' do
      it 'identifies Sorbet type errors' do
        message = "Can't set .field to value (instance of String) - need a Integer"
        expect(described_class.send(:sorbet_type_error?, message)).to be true
      end

      it 'does not match other error patterns' do
        message = "missing keyword: field"
        expect(described_class.send(:sorbet_type_error?, message)).to be false
      end
    end

    describe '.argument_error?' do
      it 'identifies missing keyword errors' do
        message = "missing keyword: field"
        expect(described_class.send(:argument_error?, message)).to be true
      end

      it 'identifies unknown keyword errors' do
        message = "unknown keyword: field"
        expect(described_class.send(:argument_error?, message)).to be true
      end

      it 'does not match Sorbet errors' do
        message = "Can't set .field to value (instance of String) - need a Integer"
        expect(described_class.send(:argument_error?, message)).to be false
      end
    end

    describe '.generate_type_specific_explanation' do
      it 'provides specific explanation for Array vs T::Array mismatch' do
        explanation = described_class.send(:generate_type_specific_explanation, 'Array', 'T::Array[PersonStruct]')
        expect(explanation).to include('plain Ruby array with hash elements')
        expect(explanation).to include('array of PersonStruct struct objects')
      end

      it 'provides specific explanation for Hash vs Struct mismatch' do
        explanation = described_class.send(:generate_type_specific_explanation, 'Hash', 'PersonStruct')
        expect(explanation).to include('plain Ruby hash')
        expect(explanation).to include('PersonStruct struct object')
      end

      it 'provides generic explanation for other mismatches' do
        explanation = described_class.send(:generate_type_specific_explanation, 'String', 'Integer')
        expect(explanation).to include('returned a String')
        expect(explanation).to include('requires Integer')
      end
    end

    describe '.generate_suggestions' do
      it 'provides specific suggestions for Array type mismatches' do
        suggestions = described_class.send(:generate_suggestions, 'items', 'Array', 'T::Array[Item]')
        expect(suggestions).to include('Check your signature uses proper T::Array[Item] typing')
        expect(suggestions).to include('Verify the LLM response format matches your expected structure')
        expect(suggestions).to include('Ensure your struct definitions are correct and accessible')
      end

      it 'includes general suggestions for all error types' do
        suggestions = described_class.send(:generate_suggestions, 'field', 'String', 'Integer')
        expect(suggestions).to include('Consider if your prompt needs clearer type instructions')
        expect(suggestions).to include('Check if the LLM model supports structured output')
      end
    end
  end
end