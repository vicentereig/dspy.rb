# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Prediction T.nilable handling' do
  describe 'basic T.nilable types' do
    class BasicNilableSignature < DSPy::Signature
      output do
        const :name, T.nilable(String)
        const :count, T.nilable(Integer)
        const :active, T.nilable(T::Boolean)
      end
    end

    it 'handles nil values correctly' do
      prediction = DSPy::Prediction.new(
        BasicNilableSignature.output_schema,
        name: nil,
        count: nil,
        active: nil
      )

      expect(prediction.name).to be_nil
      expect(prediction.count).to be_nil
      expect(prediction.active).to be_nil
    end

    it 'handles non-nil values correctly' do
      prediction = DSPy::Prediction.new(
        BasicNilableSignature.output_schema,
        name: 'test',
        count: 42,
        active: true
      )

      expect(prediction.name).to eq('test')
      expect(prediction.count).to eq(42)
      expect(prediction.active).to be(true)
    end
  end

  describe 'T.nilable with arrays' do
    class NilableArraySignature < DSPy::Signature
      output do
        const :items, T.nilable(T::Array[String])
        const :numbers, T.nilable(T::Array[Integer])
      end
    end

    it 'handles nil arrays' do
      prediction = DSPy::Prediction.new(
        NilableArraySignature.output_schema,
        items: nil,
        numbers: nil
      )

      expect(prediction.items).to be_nil
      expect(prediction.numbers).to be_nil
    end

    it 'handles empty arrays' do
      prediction = DSPy::Prediction.new(
        NilableArraySignature.output_schema,
        items: [],
        numbers: []
      )

      expect(prediction.items).to eq([])
      expect(prediction.numbers).to eq([])
    end

    it 'handles populated arrays' do
      prediction = DSPy::Prediction.new(
        NilableArraySignature.output_schema,
        items: ['a', 'b', 'c'],
        numbers: [1, 2, 3]
      )

      expect(prediction.items).to eq(['a', 'b', 'c'])
      expect(prediction.numbers).to eq([1, 2, 3])
    end
  end

  describe 'T.nilable with struct types' do
    class PredictionTestStruct < T::Struct
      const :value, String
    end

    class NilableStructSignature < DSPy::Signature
      output do
        const :data, T.nilable(PredictionTestStruct)
      end
    end

    it 'handles nil struct' do
      prediction = DSPy::Prediction.new(
        NilableStructSignature.output_schema,
        data: nil
      )

      expect(prediction.data).to be_nil
    end

    it 'handles actual struct conversion' do
      prediction = DSPy::Prediction.new(
        NilableStructSignature.output_schema,
        data: { value: 'test' }
      )

      expect(prediction.data).to be_a(PredictionTestStruct)
      expect(prediction.data.value).to eq('test')
    end
  end

  describe 'T.nilable with union types in arrays' do
    module NilableUnionTypes
      class TypeA < T::Struct
        const :type, String, default: 'a'
        const :value_a, String
      end

      class TypeB < T::Struct
        const :type, String, default: 'b'
        const :value_b, Integer
      end
    end

    class NilableUnionArraySignature < DSPy::Signature
      output do
        const :items, T.nilable(T::Array[T.any(
          NilableUnionTypes::TypeA,
          NilableUnionTypes::TypeB
        )])
      end
    end

    it 'handles nil array with union types' do
      prediction = DSPy::Prediction.new(
        NilableUnionArraySignature.output_schema,
        items: nil
      )

      expect(prediction.items).to be_nil
    end

    it 'handles empty array with union types' do
      prediction = DSPy::Prediction.new(
        NilableUnionArraySignature.output_schema,
        items: []
      )

      expect(prediction.items).to eq([])
    end

    it 'handles populated array with union type conversion' do
      prediction = DSPy::Prediction.new(
        NilableUnionArraySignature.output_schema,
        items: [
          { type: 'a', value_a: 'test' },
          { type: 'b', value_b: 42 }
        ]
      )

      expect(prediction.items).to be_an(Array)
      expect(prediction.items.length).to eq(2)
      expect(prediction.items[0]).to be_a(NilableUnionTypes::TypeA)
      expect(prediction.items[0].value_a).to eq('test')
      expect(prediction.items[1]).to be_a(NilableUnionTypes::TypeB)
      expect(prediction.items[1].value_b).to eq(42)
    end
  end

  describe 'T.nilable with enums' do
    class NilableTestPriority < T::Enum
      enums do
        Low = new('low')
        Medium = new('medium')
        High = new('high')
      end
    end

    class NilableEnumTestSignature < DSPy::Signature
      output do
        const :priority, T.nilable(NilableTestPriority)
        const :regular_priority, NilableTestPriority
      end
    end

    it 'handles nil enum values' do
      prediction = DSPy::Prediction.new(
        NilableEnumTestSignature.output_schema,
        priority: nil,
        regular_priority: 'medium'
      )

      expect(prediction.priority).to be_nil
      expect(prediction.regular_priority).to eq(NilableTestPriority::Medium)
    end

    it 'handles string to enum conversion for nilable enums' do
      prediction = DSPy::Prediction.new(
        NilableEnumTestSignature.output_schema,
        priority: 'high',
        regular_priority: 'low'
      )

      expect(prediction.priority).to eq(NilableTestPriority::High)
      expect(prediction.regular_priority).to eq(NilableTestPriority::Low)
    end

    it 'handles missing nilable enum fields' do
      prediction = DSPy::Prediction.new(
        NilableEnumTestSignature.output_schema,
        regular_priority: 'medium'
      )

      expect(prediction.priority).to be_nil
      expect(prediction.regular_priority).to eq(NilableTestPriority::Medium)
    end
  end

  describe 'complex nested T.nilable scenarios' do
    class ComplexNestedStruct < T::Struct
      const :nested_value, T.nilable(String)
      const :nested_array, T.nilable(T::Array[Integer])
    end

    class ComplexNilableSignature < DSPy::Signature
      output do
        const :wrapper, T.nilable(ComplexNestedStruct)
        const :array_of_nilable_structs, T::Array[T.nilable(ComplexNestedStruct)]
      end
    end

    it 'handles deeply nested nilable types' do
      prediction = DSPy::Prediction.new(
        ComplexNilableSignature.output_schema,
        wrapper: nil,
        array_of_nilable_structs: [nil, { nested_value: 'test', nested_array: nil }]
      )

      expect(prediction.wrapper).to be_nil
      expect(prediction.array_of_nilable_structs).to be_an(Array)
      expect(prediction.array_of_nilable_structs[0]).to be_nil
      expect(prediction.array_of_nilable_structs[1]).to be_a(ComplexNestedStruct)
      expect(prediction.array_of_nilable_structs[1].nested_value).to eq('test')
      expect(prediction.array_of_nilable_structs[1].nested_array).to be_nil
    end
  end
end