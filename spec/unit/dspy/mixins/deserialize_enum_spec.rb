# frozen_string_literal: true

require 'spec_helper'

module DeserializeEnumTest
  class Gazette < T::Enum
    enums do
      BOE = new('boe')
      BOCM = new('bocm')
      DOGC = new('dogc')
    end
  end

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  class Priority < T::Enum
    enums do
      Low = new('low')
      Medium = new('medium')
      High = new('high')
    end
  end

  class TaskWithEnum < T::Struct
    const :title, String
    const :priority, DeserializeEnumTest::Priority
  end

  class TaskWithNilableEnum < T::Struct
    const :title, String
    const :priority, T.nilable(DeserializeEnumTest::Priority)
  end

  class TaskWithEnumArray < T::Struct
    const :title, String
    const :tags, T::Array[DeserializeEnumTest::Sentiment]
  end
end

RSpec.describe 'DSPy::Mixins::TypeCoercion.deserialize_enum' do
  describe '.deserialize_enum' do
    it 'returns value unchanged when already an enum instance' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Gazette,
        DeserializeEnumTest::Gazette::BOE
      )
      expect(result).to eq(DeserializeEnumTest::Gazette::BOE)
    end

    it 'deserializes exact string match' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Gazette,
        'bocm'
      )
      expect(result).to eq(DeserializeEnumTest::Gazette::BOCM)
    end

    it 'deserializes case-insensitive match (uppercase from LLM)' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Gazette,
        'BOCM'
      )
      expect(result).to eq(DeserializeEnumTest::Gazette::BOCM)
    end

    it 'deserializes mixed case match' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Gazette,
        'Bocm'
      )
      expect(result).to eq(DeserializeEnumTest::Gazette::BOCM)
    end

    it 'returns nil for completely invalid value' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Gazette,
        'nonexistent'
      )
      expect(result).to be_nil
    end

    it 'handles integer-like values gracefully' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Gazette,
        42
      )
      expect(result).to be_nil
    end

    it 'works with multi-word enum values' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Sentiment,
        'POSITIVE'
      )
      expect(result).to eq(DeserializeEnumTest::Sentiment::Positive)
    end

    it 'prefers exact match over case-insensitive match' do
      result = DSPy::Mixins::TypeCoercion.deserialize_enum(
        DeserializeEnumTest::Gazette,
        'boe'
      )
      expect(result).to eq(DeserializeEnumTest::Gazette::BOE)
    end
  end

  describe 'integration with coerce_enum_value' do
    let(:coercer) do
      Class.new do
        include DSPy::Mixins::TypeCoercion
        def test_coerce(value, type)
          coerce_value_to_type(value, type)
        end
      end.new
    end

    it 'case-insensitive enum coercion via the mixin dispatch' do
      enum_type = T::Utils.coerce(DeserializeEnumTest::Gazette)
      result = coercer.test_coerce('BOCM', enum_type)
      expect(result).to eq(DeserializeEnumTest::Gazette::BOCM)
    end

    it 'case-insensitive enum coercion returns original on total mismatch' do
      enum_type = T::Utils.coerce(DeserializeEnumTest::Gazette)
      result = coercer.test_coerce('nonexistent', enum_type)
      expect(result).to eq('nonexistent')
    end
  end

  describe 'integration with Prediction' do
    it 'handles case-insensitive enum at top level' do
      sig_class = Class.new(DSPy::Signature) do
        output do
          const :gazette, DeserializeEnumTest::Gazette
        end
      end

      prediction = DSPy::Prediction.new(
        sig_class.output_schema,
        gazette: 'BOCM'
      )

      expect(prediction.gazette).to eq(DeserializeEnumTest::Gazette::BOCM)
    end

    it 'handles case-insensitive enum in nested struct' do
      sig_class = Class.new(DSPy::Signature) do
        output do
          const :task, DeserializeEnumTest::TaskWithEnum
        end
      end

      prediction = DSPy::Prediction.new(
        sig_class.output_schema,
        task: { title: 'Do thing', priority: 'HIGH' }
      )

      expect(prediction.task).to be_a(DeserializeEnumTest::TaskWithEnum)
      expect(prediction.task.priority).to eq(DeserializeEnumTest::Priority::High)
    end

    it 'handles case-insensitive enum in nilable field' do
      sig_class = Class.new(DSPy::Signature) do
        output do
          const :task, DeserializeEnumTest::TaskWithNilableEnum
        end
      end

      prediction = DSPy::Prediction.new(
        sig_class.output_schema,
        task: { title: 'Do thing', priority: 'HIGH' }
      )

      expect(prediction.task).to be_a(DeserializeEnumTest::TaskWithNilableEnum)
      expect(prediction.task.priority).to eq(DeserializeEnumTest::Priority::High)
    end

    it 'handles case-insensitive enum in array elements' do
      sig_class = Class.new(DSPy::Signature) do
        output do
          const :task, DeserializeEnumTest::TaskWithEnumArray
        end
      end

      prediction = DSPy::Prediction.new(
        sig_class.output_schema,
        task: { title: 'Do thing', tags: ['POSITIVE', 'Negative', 'neutral'] }
      )

      expect(prediction.task.tags).to eq([
        DeserializeEnumTest::Sentiment::Positive,
        DeserializeEnumTest::Sentiment::Negative,
        DeserializeEnumTest::Sentiment::Neutral
      ])
    end

    it 'returns nil for completely invalid enum (graceful degradation)' do
      sig_class = Class.new(DSPy::Signature) do
        output do
          const :gazette, DeserializeEnumTest::Gazette
        end
      end

      # After centralization, invalid enums should not crash
      # They should return the original string value
      prediction = DSPy::Prediction.new(
        sig_class.output_schema,
        gazette: 'completely_invalid'
      )

      expect(prediction.gazette).to eq('completely_invalid')
    end
  end
end
