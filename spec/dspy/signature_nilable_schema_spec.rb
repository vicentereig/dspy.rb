# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Signature T.nilable JSON Schema Generation' do
  describe 'basic T.nilable types' do
    class BasicNilableSchemaSignature < DSPy::Signature
      output do
        const :name, T.nilable(String)
        const :count, T.nilable(Integer)  
        const :score, T.nilable(Float)
        const :active, T.nilable(T::Boolean)
      end
    end

    it 'generates correct JSON schema for T.nilable(String)' do
      schema = BasicNilableSchemaSignature.output_json_schema
      
      expect(schema[:properties][:name]).to eq({
        type: ['string', 'null']
      })
    end

    it 'generates correct JSON schema for T.nilable(Integer)' do
      schema = BasicNilableSchemaSignature.output_json_schema
      
      expect(schema[:properties][:count]).to eq({
        type: ['integer', 'null']
      })
    end

    it 'generates correct JSON schema for T.nilable(Float)' do
      schema = BasicNilableSchemaSignature.output_json_schema
      
      expect(schema[:properties][:score]).to eq({
        type: ['number', 'null']
      })
    end

    it 'generates correct JSON schema for T.nilable(T::Boolean)' do
      schema = BasicNilableSchemaSignature.output_json_schema
      
      # T.nilable(T::Boolean) should generate simple nilable boolean schema
      expect(schema[:properties][:active]).to eq({
        type: ['boolean', 'null']
      })
    end
  end

  describe 'T.nilable with enums' do
    class Status < T::Enum
      enums do
        Active = new('active')
        Inactive = new('inactive')
        Pending = new('pending')
      end
    end

    class NilableEnumSignature < DSPy::Signature
      output do
        const :status, T.nilable(Status)
      end
    end

    it 'generates correct JSON schema for T.nilable(Enum)' do
      schema = NilableEnumSignature.output_json_schema
      
      expect(schema[:properties][:status]).to eq({
        type: ['string', 'null'],
        enum: ['active', 'inactive', 'pending']
      })
    end
  end

  describe 'T.nilable with arrays' do
    class NilableArraySchemaSignature < DSPy::Signature
      output do
        const :items, T.nilable(T::Array[String])
        const :numbers, T.nilable(T::Array[Integer])
      end
    end

    it 'generates correct JSON schema for T.nilable(Array[String])' do
      schema = NilableArraySchemaSignature.output_json_schema
      
      expect(schema[:properties][:items]).to eq({
        type: ['array', 'null'],
        items: { type: 'string' }
      })
    end

    it 'generates correct JSON schema for T.nilable(Array[Integer])' do
      schema = NilableArraySchemaSignature.output_json_schema
      
      expect(schema[:properties][:numbers]).to eq({
        type: ['array', 'null'],
        items: { type: 'integer' }
      })
    end
  end

  describe 'T.nilable with custom structs' do
    class TestStruct < T::Struct
      const :value, String
      const :count, Integer
    end

    class NilableStructSchemaSignature < DSPy::Signature
      output do
        const :data, T.nilable(TestStruct)
      end
    end

    it 'generates correct JSON schema for T.nilable(CustomStruct)' do
      schema = NilableStructSchemaSignature.output_json_schema
      
      expect(schema[:properties][:data]).to eq({
        type: ['object', 'null'],
        properties: {
          _type: {
            type: 'string',
            const: 'TestStruct'
          },
          value: { type: 'string' },
          count: { type: 'integer' }
        },
        required: ['_type', 'value', 'count'],
        description: "#{TestStruct.name} struct"
      })
    end
  end

  describe 'T.nilable with hash types' do
    class NilableHashSchemaSignature < DSPy::Signature
      output do
        const :metadata, T.nilable(T::Hash[String, Integer])
      end
    end

    it 'generates correct JSON schema for T.nilable(Hash[String, Integer])' do
      schema = NilableHashSchemaSignature.output_json_schema
      
      expect(schema[:properties][:metadata]).to eq({
        type: ['object', 'null'],
        propertyNames: { type: 'string' },
        additionalProperties: { type: 'integer' },
        description: 'A mapping where keys are strings and values are integers'
      })
    end
  end

  describe 'complex T.nilable union types' do
    class UnionTypeA < T::Struct
      const :type, String, default: 'a'
      const :value_a, String
    end

    class UnionTypeB < T::Struct
      const :type, String, default: 'b'
      const :value_b, Integer
    end

    class NilableUnionSchemaSignature < DSPy::Signature
      output do
        const :choice, T.nilable(T.any(UnionTypeA, UnionTypeB))
      end
    end

    it 'generates correct JSON schema for T.nilable(T.any(...))' do
      schema = NilableUnionSchemaSignature.output_json_schema
      
      expect(schema[:properties][:choice]).to include({
        oneOf: [
          {
            type: 'object',
            properties: {
              _type: { type: 'string', const: 'UnionTypeA' },
              type: { type: 'string' },
              value_a: { type: 'string' }
            },
            required: ['_type', 'type', 'value_a'],
            description: "#{UnionTypeA.name} struct"
          },
          {
            type: 'object', 
            properties: {
              _type: { type: 'string', const: 'UnionTypeB' },
              type: { type: 'string' },
              value_b: { type: 'integer' }
            },
            required: ['_type', 'type', 'value_b'],
            description: "#{UnionTypeB.name} struct"
          },
          { type: 'null' }
        ],
        description: 'Union of multiple types'
      })
    end
  end

  describe 'nested T.nilable scenarios' do
    class NestedStruct < T::Struct
      const :name, String
      const :optional_value, T.nilable(String)
      const :optional_list, T.nilable(T::Array[Integer])
    end

    class NestedNilableSignature < DSPy::Signature
      output do
        const :wrapper, T.nilable(NestedStruct)
        const :array_of_nilable, T::Array[T.nilable(String)]
      end
    end

    it 'generates correct schema for nested struct with nilable fields' do
      schema = NestedNilableSignature.output_json_schema
      
      # Check the nilable wrapper struct
      expect(schema[:properties][:wrapper]).to eq({
        type: ['object', 'null'],
        properties: {
          _type: { type: 'string', const: 'NestedStruct' },
          name: { type: 'string' },
          optional_value: { type: ['string', 'null'] },
          optional_list: {
            type: ['array', 'null'],
            items: { type: 'integer' }
          }
        },
        required: ['_type', 'name'],
        description: "#{NestedStruct.name} struct"
      })
    end

    it 'generates correct schema for array of nilable items' do
      schema = NestedNilableSignature.output_json_schema
      
      expect(schema[:properties][:array_of_nilable]).to eq({
        type: 'array',
        items: { type: ['string', 'null'] }
      })
    end
  end

  describe 'required field handling with nilable types' do
    class RequiredNilableSignature < DSPy::Signature
      output do
        const :required_nilable, T.nilable(String)
        const :optional_nilable, T.nilable(String), default: nil
        const :required_regular, String
      end
    end

    it 'correctly marks nilable fields as required unless they have defaults' do
      schema = RequiredNilableSignature.output_json_schema
      
      expect(schema[:required]).to include('required_nilable')
      expect(schema[:required]).not_to include('optional_nilable')
      expect(schema[:required]).to include('required_regular')
    end
  end

  describe 'edge cases and error handling' do
    # Test case for empty union (shouldn't happen in practice but test robustness)
    it 'handles malformed types gracefully' do
      # This is more of a robustness test - the actual implementation
      # should handle edge cases without crashing
      
      class EdgeCaseSignature < DSPy::Signature
        output do
          const :safe_field, String
        end
      end

      expect {
        EdgeCaseSignature.output_json_schema
      }.not_to raise_error
    end

    # Test for deeply nested nilable structures
    class DeeplyNestedStruct < T::Struct
      const :level1, T.nilable(String)
      const :level2, T.nilable(T::Array[T.nilable(Integer)])
    end

    class DeepNilableSignature < DSPy::Signature
      output do
        const :deep, T.nilable(T::Array[T.nilable(DeeplyNestedStruct)])
      end
    end

    it 'handles deeply nested nilable types' do
      schema = DeepNilableSignature.output_json_schema
      
      # Should generate proper schema without errors
      expect(schema[:properties][:deep]).to include({
        type: ['array', 'null']
      })
      
      # The items should be objects that can also be null
      items_schema = schema[:properties][:deep][:items]
      expect(items_schema[:type]).to include('object')
      expect(items_schema[:type]).to include('null')
      expect(items_schema[:properties][:level1][:type]).to eq(['string', 'null'])
      expect(items_schema[:properties][:level2][:type]).to eq(['array', 'null'])
      expect(items_schema[:properties][:level2][:items][:type]).to eq(['integer', 'null'])
    end

    # Test multiple nilable fields in one signature
    class MultiNilableSignature < DSPy::Signature
      output do
        const :string_field, T.nilable(String)
        const :int_field, T.nilable(Integer) 
        const :array_field, T.nilable(T::Array[String])
        const :regular_field, String  # Non-nilable for comparison
      end
    end

    it 'generates correct schema for signature with multiple nilable fields' do
      schema = MultiNilableSignature.output_json_schema
      
      # Nilable fields should have null in their type array
      expect(schema[:properties][:string_field][:type]).to eq(['string', 'null'])
      expect(schema[:properties][:int_field][:type]).to eq(['integer', 'null'])
      expect(schema[:properties][:array_field][:type]).to eq(['array', 'null'])
      
      # Regular field should not have null
      expect(schema[:properties][:regular_field][:type]).to eq('string')
      
      # All required fields should be present (nilable doesn't affect required unless there's a default)
      expect(schema[:required]).to include('string_field', 'int_field', 'array_field', 'regular_field')
    end
  end
end