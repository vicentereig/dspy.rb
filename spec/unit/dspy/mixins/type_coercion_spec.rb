# frozen_string_literal: true

require 'spec_helper'

# Test structs for union type handling
module TestStructs
  # Test enums scoped to avoid conflicts
  class Priority < T::Enum
    enums do
      Low = new('low')
      Medium = new('medium')
      High = new('high')
    end
  end
  class SearchAction < T::Struct
    const :query, String
    const :max_results, Integer, default: 5
  end

  class AnswerAction < T::Struct
    const :content, String
    const :confidence, Float
  end

  class TaskAction < T::Struct
    const :title, String
    const :priority, TestStructs::Priority  # Enum field
  end

  # Test nested struct coercion
  class Address < T::Struct
    const :street, String
    const :city, String
  end

  class Person < T::Struct
    const :name, String
    const :address, TestStructs::Address
  end

  # Test struct with legitimate _type field
  class MetaStruct < T::Struct
    const :_type, String  # This should be preserved
    const :data, String
  end
end

RSpec.describe DSPy::Mixins::TypeCoercion do
  # Create a test class that includes the mixin
  let(:test_class) do
    Class.new do
      include DSPy::Mixins::TypeCoercion

      def test_coerce(value, type)
        coerce_value_to_type(value, type)
      end

      def test_coerce_attributes(attributes, props)
        coerce_output_attributes(attributes, props)
      end
    end
  end

  let(:instance) { test_class.new }

  describe '#coerce_value_to_type' do
    context 'with union types (T.any)' do
      let(:union_type) { T.any(TestStructs::SearchAction, TestStructs::AnswerAction) }

      it 'converts Hash with enum fields within union types' do
        # Test with union type including a struct with enum field
        union_with_enum = T.any(TestStructs::TaskAction, TestStructs::AnswerAction)

        hash_value = {
          "_type" => "TaskAction",
          "title" => "Important task",
          "priority" => "high"  # String that needs enum conversion
        }

        result = instance.test_coerce(hash_value, union_with_enum)

        expect(result).to be_a(TestStructs::TaskAction)
        expect(result.title).to eq("Important task")
        expect(result.priority).to be_a(TestStructs::Priority)
        expect(result.priority).to eq(TestStructs::Priority::High)
      end

      it 'converts Hash with _type discriminator to appropriate struct' do
        # Test AnswerAction conversion
        hash_value = {
          "_type" => "AnswerAction",
          "content" => "2 + 2 = 4",
          "confidence" => 1.0
        }

        result = instance.test_coerce(hash_value, union_type)

        expect(result).to be_a(TestStructs::AnswerAction)
        expect(result.content).to eq("2 + 2 = 4")
        expect(result.confidence).to eq(1.0)
      end

      it 'converts Hash with symbol keys and _type to appropriate struct' do
        hash_value = {
          _type: "SearchAction",
          query: "AI safety research",
          max_results: 10
        }

        result = instance.test_coerce(hash_value, union_type)

        expect(result).to be_a(TestStructs::SearchAction)
        expect(result.query).to eq("AI safety research")
        expect(result.max_results).to eq(10)
      end

      it 'returns original value if no _type field present' do
        hash_value = {
          "query" => "test query",
          "max_results" => 5
        }

        result = instance.test_coerce(hash_value, union_type)

        # Without _type, it should return the original hash
        expect(result).to eq(hash_value)
      end

      it 'returns original value if _type does not match any union variant' do
        hash_value = {
          "_type" => "UnknownAction",
          "data" => "some data"
        }

        result = instance.test_coerce(hash_value, union_type)

        expect(result).to eq(hash_value)
      end

      it 'ignores extra fields not defined in the struct when converting union types' do
        # This tests the fix for issue #59
        hash_value = {
          "_type" => "AnswerAction",
          "content" => "The answer is 42",
          "confidence" => 0.95,
          "synthesis" => "Extra field that should be ignored",  # Not defined in AnswerAction
          "extra_data" => { "foo" => "bar" }  # Another extra field
        }

        result = instance.test_coerce(hash_value, union_type)

        # Should successfully create the struct without the extra fields
        expect(result).to be_a(TestStructs::AnswerAction)
        expect(result.content).to eq("The answer is 42")
        expect(result.confidence).to eq(0.95)

        # Verify the struct doesn't have the extra fields
        expect { result.synthesis }.to raise_error(NoMethodError)
        expect { result.extra_data }.to raise_error(NoMethodError)
      end
    end

    context 'with existing type handling' do
      it 'still handles simple types correctly' do
        # Use T::Utils.coerce to get proper Sorbet type objects
        float_type = T::Utils.coerce(Float)
        integer_type = T::Utils.coerce(Integer)

        expect(instance.test_coerce("3.14", float_type)).to eq(3.14)
        expect(instance.test_coerce("42", integer_type)).to eq(42)
      end

      it 'still handles arrays correctly' do
        array_type = T::Array[Integer]
        result = instance.test_coerce(["1", "2", "3"], array_type)
        expect(result).to eq([1, 2, 3])
      end

      it 'coerces scalars into strings when required' do
        string_type = T::Utils.coerce(String)
        expect(instance.test_coerce(123, string_type)).to eq("123")
      end

      it 'coerces array elements into strings when required' do
        array_type = T::Array[String]
        result = instance.test_coerce([1, :symbol, 3.5], array_type)
        expect(result).to eq(["1", "symbol", "3.5"])
      end

      it 'still handles regular structs correctly' do
        struct_type = TestStructs::AnswerAction
        hash_value = { content: "Answer", confidence: 0.9 }

        result = instance.test_coerce(hash_value, struct_type)

        expect(result).to be_a(TestStructs::AnswerAction)
        expect(result.content).to eq("Answer")
        expect(result.confidence).to eq(0.9)
      end
    end

    context 'with direct struct fields (non-union)' do
      it 'filters out _type field when coercing direct struct' do
        struct_type = TestStructs::AnswerAction
        hash_value = {
          "_type" => "AnswerAction",  # This should be filtered out
          "content" => "Direct struct test",
          "confidence" => 0.85
        }

        result = instance.test_coerce(hash_value, struct_type)

        expect(result).to be_a(TestStructs::AnswerAction)
        expect(result.content).to eq("Direct struct test")
        expect(result.confidence).to eq(0.85)
      end

      it 'filters out _type field with symbol keys' do
        struct_type = TestStructs::AnswerAction
        hash_value = {
          _type: "AnswerAction",  # This should be filtered out
          content: "Symbol key test",
          confidence: 0.75
        }

        result = instance.test_coerce(hash_value, struct_type)

        expect(result).to be_a(TestStructs::AnswerAction)
        expect(result.content).to eq("Symbol key test")
        expect(result.confidence).to eq(0.75)
      end

      it 'preserves legitimate _type field when it is part of the struct definition' do
        struct_type = TestStructs::MetaStruct
        hash_value = {
          "_type" => "important_metadata",  # This should be preserved as it's a real field
          "data" => "some data"
        }

        result = instance.test_coerce(hash_value, struct_type)

        expect(result).to be_a(TestStructs::MetaStruct)
        expect(result._type).to eq("important_metadata")
        expect(result.data).to eq("some data")
      end
    end

    context 'with nested struct coercion' do
      it 'recursively coerces nested structs and removes _type at all levels' do
        struct_type = TestStructs::Person
        hash_value = {
          "_type" => "Person",  # Should be filtered out
          "name" => "John Doe",
          "address" => {
            "_type" => "Address",  # Should also be filtered out
            "street" => "123 Main St",
            "city" => "Anytown"
          }
        }

        result = instance.test_coerce(hash_value, struct_type)

        expect(result).to be_a(TestStructs::Person)
        expect(result.name).to eq("John Doe")
        expect(result.address).to be_a(TestStructs::Address)
        expect(result.address.street).to eq("123 Main St")
        expect(result.address.city).to eq("Anytown")
      end

      it 'handles deeply nested structs' do
        # Create a more complex nested structure on the fly for testing
        company_struct = Class.new(T::Struct) do
          const :name, String
          const :address, TestStructs::Address
        end

        employee_struct = Class.new(T::Struct) do
          const :person, TestStructs::Person
          const :company, company_struct
        end

        hash_value = {
          "_type" => "Employee",
          "person" => {
            "_type" => "Person",
            "name" => "Jane Smith",
            "address" => {
              "_type" => "Address",
              "street" => "456 Oak Ave",
              "city" => "Somewhere"
            }
          },
          "company" => {
            "_type" => "Company",
            "name" => "Tech Corp",
            "address" => {
              "_type" => "Address",
              "street" => "789 Business Blvd",
              "city" => "Downtown"
            }
          }
        }

        result = instance.test_coerce(hash_value, employee_struct)

        expect(result.person).to be_a(TestStructs::Person)
        expect(result.person.name).to eq("Jane Smith")
        expect(result.person.address.street).to eq("456 Oak Ave")
        expect(result.company.name).to eq("Tech Corp")
        expect(result.company.address.city).to eq("Downtown")
      end
    end

    context 'with array of structs' do
      it 'coerces array elements and removes _type from each' do
        array_type = T::Array[TestStructs::AnswerAction]
        hash_values = [
          {
            "_type" => "AnswerAction",
            "content" => "First answer",
            "confidence" => 0.9
          },
          {
            "_type" => "AnswerAction",
            "content" => "Second answer",
            "confidence" => 0.8
          }
        ]

        result = instance.test_coerce(hash_values, array_type)

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)

        expect(result[0]).to be_a(TestStructs::AnswerAction)
        expect(result[0].content).to eq("First answer")
        expect(result[0].confidence).to eq(0.9)

        expect(result[1]).to be_a(TestStructs::AnswerAction)
        expect(result[1].content).to eq("Second answer")
        expect(result[1].confidence).to eq(0.8)
      end
    end

    context 'with edge cases' do
      it 'handles minimal hash with required fields' do
        struct_type = TestStructs::SearchAction  # Has default values
        hash_value = { 
          "_type" => "SearchAction", 
          "query" => "test query"  # Required field
        }

        result = instance.test_coerce(hash_value, struct_type)

        expect(result).to be_a(TestStructs::SearchAction)
        expect(result.query).to eq("test query")
        expect(result.max_results).to eq(5)  # Default value
      end

      it 'handles nil values gracefully' do
        struct_type = TestStructs::AnswerAction

        result = instance.test_coerce(nil, struct_type)

        expect(result).to be_nil
      end

      it 'handles non-hash values gracefully' do
        struct_type = TestStructs::AnswerAction

        result = instance.test_coerce("not a hash", struct_type)

        expect(result).to eq("not a hash")
      end
    end
  end

  describe '#coerce_output_attributes' do
    it 'handles mixed attributes including union types' do
      props = {
        status: { type: T::Utils.coerce(String) },
        action: { type: T.any(TestStructs::SearchAction, TestStructs::AnswerAction) },
        confidence: { type: T::Utils.coerce(Float) }
      }

      attributes = {
        status: "success",
        action: {
          "_type" => "AnswerAction",
          "content" => "The answer is 42",
          "confidence" => 0.95
        },
        confidence: "0.99"
      }

      result = instance.test_coerce_attributes(attributes, props)

      expect(result[:status]).to eq("success")
      expect(result[:action]).to be_a(TestStructs::AnswerAction)
      expect(result[:action].content).to eq("The answer is 42")
      expect(result[:confidence]).to eq(0.99)
    end
  end
end
