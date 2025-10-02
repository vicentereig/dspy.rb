require 'spec_helper'
require 'ostruct'
require 'dspy/example'
require 'dspy/signature'

# Test signatures for Example testing
class ExampleMath < DSPy::Signature
  description "Solve arithmetic problems with explanations."

  input do
    const :problem, String, description: "A math problem to solve"
    const :difficulty, String, description: "Easy, Medium, or Hard"
  end

  output do
    const :answer, String, description: "The numerical answer"
    const :explanation, String, description: "Step-by-step solution"
  end
end

class SimpleClassify < DSPy::Signature
  description "Classify text sentiment."

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :text, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

class OptionalFields < DSPy::Signature
  description "Test signature with optional fields."

  input do
    const :required_field, String
    const :optional_field, T.nilable(String), default: nil
  end

  output do
    const :result, String
    const :optional_result, T.nilable(Integer), default: nil
  end
end

RSpec.describe DSPy::Example do
  describe 'initialization' do
    it 'creates example with valid input and expected output' do
      example = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "2 + 3", difficulty: "Easy" },
        expected: { answer: "5", explanation: "Add 2 and 3 to get 5" }
      )
      
      expect(example.signature_class).to eq(ExampleMath)
      expect(example.input).to be_a(T::Struct)
      expect(example.expected).to be_a(T::Struct)
    end

    it 'validates input against signature schema' do
      expect {
        DSPy::Example.new(
          signature_class: ExampleMath,
          input: { problem: "2 + 3" }, # Missing difficulty
          expected: { answer: "5", explanation: "Add 2 and 3 to get 5" }
        )
      }.to raise_error(ArgumentError, /Invalid input/)
    end

    it 'validates expected output against signature schema' do
      expect {
        DSPy::Example.new(
          signature_class: ExampleMath,
          input: { problem: "2 + 3", difficulty: "Easy" },
          expected: { answer: "5" } # Missing explanation
        )
      }.to raise_error(ArgumentError, /Invalid expected/)
    end

    it 'handles type validation errors' do
      expect {
        DSPy::Example.new(
          signature_class: SimpleClassify,
          input: { text: "Hello world" },
          expected: { sentiment: "invalid_sentiment", confidence: 0.9 } # Invalid enum
        )
      }.to raise_error(TypeError, /Type error/)
    end

    it 'accepts optional id and metadata' do
      example = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "5 × 6", difficulty: "Medium" },
        expected: { answer: "30", explanation: "Multiply 5 by 6" },
        id: "math_001",
        metadata: { source: "textbook", chapter: 2 }
      )
      
      expect(example.id).to eq("math_001")
      expect(example.metadata[:source]).to eq("textbook")
    end

    it 'works with signatures containing optional fields' do
      example = DSPy::Example.new(
        signature_class: OptionalFields,
        input: { required_field: "test" }, # optional_field defaults to nil
        expected: { result: "processed" } # optional_result defaults to nil
      )
      
      expect(example.input.required_field).to eq("test")
      expect(example.input.optional_field).to be_nil
      expect(example.expected.result).to eq("processed")
      expect(example.expected.optional_result).to be_nil
    end
  end

  describe '#input_values' do
    it 'converts input struct to hash' do
      example = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "7 - 3", difficulty: "Easy" },
        expected: { answer: "4", explanation: "Subtract 3 from 7" }
      )
      
      input_hash = example.input_values
      expect(input_hash).to eq({ problem: "7 - 3", difficulty: "Easy" })
    end
  end

  describe '#expected_values' do
    it 'converts expected struct to hash' do
      example = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "8 ÷ 2", difficulty: "Easy" },
        expected: { answer: "4", explanation: "Divide 8 by 2" }
      )
      
      expected_hash = example.expected_values
      expect(expected_hash).to eq({ answer: "4", explanation: "Divide 8 by 2" })
    end
  end

  describe '#matches_prediction?' do
    let(:example) do
      DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "10 - 6", difficulty: "Easy" },
        expected: { answer: "4", explanation: "Subtract 6 from 10" }
      )
    end

    it 'returns true for matching struct prediction' do
      prediction = ExampleMath.output_struct_class.new(
        answer: "4",
        explanation: "Subtract 6 from 10"
      )
      
      expect(example.matches_prediction?(prediction)).to be(true)
    end

    it 'returns true for matching hash prediction' do
      prediction = { answer: "4", explanation: "Subtract 6 from 10" }
      
      expect(example.matches_prediction?(prediction)).to be(true)
    end

    it 'returns true for matching object prediction' do
      prediction = OpenStruct.new(answer: "4", explanation: "Subtract 6 from 10")
      
      expect(example.matches_prediction?(prediction)).to be(true)
    end

    it 'returns false for non-matching prediction' do
      prediction = { answer: "5", explanation: "Subtract 6 from 10" }
      
      expect(example.matches_prediction?(prediction)).to be(false)
    end

    it 'returns false for nil prediction' do
      expect(example.matches_prediction?(nil)).to be(false)
    end

    it 'returns false for prediction missing fields' do
      prediction = { answer: "4" } # Missing explanation
      
      expect(example.matches_prediction?(prediction)).to be(false)
    end
  end

  describe 'serialization' do
    let(:example) do
      DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "12 ÷ 3", difficulty: "Medium" },
        expected: { answer: "4", explanation: "Divide 12 by 3" },
        id: "math_002",
        metadata: { source: "quiz" }
      )
    end

    describe '#to_h' do
      it 'serializes example to hash' do
        hash = example.to_h
        
        expect(hash[:signature_class]).to eq("ExampleMath")
        expect(hash[:input]).to eq({ problem: "12 ÷ 3", difficulty: "Medium" })
        expect(hash[:expected]).to eq({ answer: "4", explanation: "Divide 12 by 3" })
        expect(hash[:id]).to eq("math_002")
        expect(hash[:metadata]).to eq({ source: "quiz" })
      end

      it 'excludes nil id and metadata' do
        simple_example = DSPy::Example.new(
          signature_class: ExampleMath,
          input: { problem: "1 + 1", difficulty: "Easy" },
          expected: { answer: "2", explanation: "Add 1 and 1" }
        )
        
        hash = simple_example.to_h
        expect(hash).not_to have_key(:id)
        expect(hash).not_to have_key(:metadata)
      end
    end

    describe '.from_h' do
      it 'deserializes example from hash' do
        hash = {
          signature_class: "ExampleMath",
          input: { problem: "15 - 7", difficulty: "Easy" },
          expected: { answer: "8", explanation: "Subtract 7 from 15" },
          id: "math_003"
        }
        
        # Create a mock signature registry
        registry = { "ExampleMath" => ExampleMath }
        restored = DSPy::Example.from_h(hash, signature_registry: registry)
        
        expect(restored.signature_class).to eq(ExampleMath)
        expect(restored.input_values).to eq(hash[:input])
        expect(restored.expected_values).to eq(hash[:expected])
        expect(restored.id).to eq("math_003")
      end

      it 'resolves signature class from constant when no registry provided' do
        hash = {
          signature_class: "ExampleMath",
          input: { problem: "9 × 2", difficulty: "Easy" },
          expected: { answer: "18", explanation: "Multiply 9 by 2" }
        }
        
        restored = DSPy::Example.from_h(hash)
        expect(restored.signature_class).to eq(ExampleMath)
      end
    end
  end


  describe '.validate_batch' do
    it 'validates multiple examples successfully' do
      examples_data = [
        {
          input: { problem: "4 + 5", difficulty: "Easy" },
          expected: { answer: "9", explanation: "Add 4 and 5" }
        },
        {
          input: { problem: "8 - 3", difficulty: "Easy" },
          expected: { answer: "5", explanation: "Subtract 3 from 8" }
        }
      ]
      
      examples = DSPy::Example.validate_batch(ExampleMath, examples_data)
      
      expect(examples.length).to eq(2)
      expect(examples.all? { |ex| ex.is_a?(DSPy::Example) }).to be(true)
    end

    it 'collects and reports validation errors' do
      examples_data = [
        {
          input: { problem: "Good example", difficulty: "Easy" },
          expected: { answer: "Good", explanation: "Good" }
        },
        {
          input: { problem: "Missing difficulty" }, # Missing required field
          expected: { answer: "Bad", explanation: "Bad" }
        },
        {
          input: { problem: "Another good", difficulty: "Easy" },
          expected: { answer: "Missing explanation" } # Missing required field
        }
      ]
      
      expect {
        DSPy::Example.validate_batch(ExampleMath, examples_data)
      }.to raise_error(ArgumentError, /Validation errors/)
    end
  end

  describe 'equality' do
    it 'compares examples correctly' do
      example1 = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "7 + 8", difficulty: "Easy" },
        expected: { answer: "15", explanation: "Add 7 and 8" }
      )
      
      example2 = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "7 + 8", difficulty: "Easy" },
        expected: { answer: "15", explanation: "Add 7 and 8" }
      )
      
      expect(example1).to eq(example2)
    end

    it 'returns false for different examples' do
      example1 = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "7 + 8", difficulty: "Easy" },
        expected: { answer: "15", explanation: "Add 7 and 8" }
      )
      
      example2 = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "7 + 8", difficulty: "Easy" },
        expected: { answer: "16", explanation: "Add 7 and 8" } # Different answer
      )
      
      expect(example1).not_to eq(example2)
    end

    it 'returns false for different signature classes' do
      example1 = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "7 + 8", difficulty: "Easy" },
        expected: { answer: "15", explanation: "Add 7 and 8" }
      )
      
      example2 = DSPy::Example.new(
        signature_class: SimpleClassify,
        input: { text: "Hello" },
        expected: { sentiment: SimpleClassify::Sentiment::Positive, confidence: 0.9 }
      )
      
      expect(example1).not_to eq(example2)
    end
  end

  describe 'string representation' do
    it 'provides readable to_s output' do
      example = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "20 ÷ 4", difficulty: "Easy" },
        expected: { answer: "5", explanation: "Divide 20 by 4" }
      )
      
      string_repr = example.to_s
      expect(string_repr).to include("DSPy::Example")
      expect(string_repr).to include("ExampleMath")
      expect(string_repr).to include("20 ÷ 4")
    end

    it 'provides same output for inspect' do
      example = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "11 - 4", difficulty: "Easy" },
        expected: { answer: "7", explanation: "Subtract 4 from 11" }
      )
      
      expect(example.inspect).to eq(example.to_s)
    end
  end

  describe 'round-trip serialization' do
    it 'preserves all data through serialization and deserialization' do
      original = DSPy::Example.new(
        signature_class: ExampleMath,
        input: { problem: "13 + 7", difficulty: "Medium" },
        expected: { answer: "20", explanation: "Add 13 and 7" },
        id: "math_final",
        metadata: { difficulty_score: 0.6 }
      )
      
      hash = original.to_h
      registry = { "ExampleMath" => ExampleMath }
      restored = DSPy::Example.from_h(hash, signature_registry: registry)
      
      expect(restored).to eq(original)
      expect(restored.id).to eq(original.id)
      expect(restored.metadata).to eq(original.metadata)
    end
  end
end