# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Scores::ScoreEvent do
  describe 'initialization' do
    it 'creates a score event with required parameters' do
      event = described_class.new(
        name: 'accuracy',
        value: 0.95
      )

      expect(event.name).to eq('accuracy')
      expect(event.value).to eq(0.95)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Numeric)
    end

    it 'creates a score event with all parameters' do
      event = described_class.new(
        name: 'accuracy',
        value: 0.95,
        data_type: DSPy::Scores::DataType::Numeric,
        comment: 'Exact match on answer field',
        trace_id: 'trace-123',
        observation_id: 'span-456'
      )

      expect(event.name).to eq('accuracy')
      expect(event.value).to eq(0.95)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Numeric)
      expect(event.comment).to eq('Exact match on answer field')
      expect(event.trace_id).to eq('trace-123')
      expect(event.observation_id).to eq('span-456')
    end

    it 'generates a unique id if not provided' do
      event = described_class.new(name: 'test', value: 1.0)

      expect(event.id).to be_a(String)
      expect(event.id).not_to be_empty
    end

    it 'uses provided id when given' do
      event = described_class.new(
        name: 'test',
        value: 1.0,
        id: 'custom-id-123'
      )

      expect(event.id).to eq('custom-id-123')
    end
  end

  describe 'data types' do
    it 'supports numeric data type' do
      event = described_class.new(
        name: 'score',
        value: 0.85,
        data_type: DSPy::Scores::DataType::Numeric
      )

      expect(event.data_type).to eq(DSPy::Scores::DataType::Numeric)
    end

    it 'supports boolean data type with true value' do
      event = described_class.new(
        name: 'is_valid',
        value: 1,
        data_type: DSPy::Scores::DataType::Boolean
      )

      expect(event.data_type).to eq(DSPy::Scores::DataType::Boolean)
      expect(event.value).to eq(1)
    end

    it 'supports boolean data type with false value' do
      event = described_class.new(
        name: 'is_valid',
        value: 0,
        data_type: DSPy::Scores::DataType::Boolean
      )

      expect(event.value).to eq(0)
    end

    it 'supports categorical data type' do
      event = described_class.new(
        name: 'sentiment',
        value: 'positive',
        data_type: DSPy::Scores::DataType::Categorical
      )

      expect(event.data_type).to eq(DSPy::Scores::DataType::Categorical)
      expect(event.value).to eq('positive')
    end
  end

  describe '#to_langfuse_payload' do
    it 'serializes to Langfuse API format' do
      event = described_class.new(
        id: 'score-id-123',
        name: 'accuracy',
        value: 0.95,
        data_type: DSPy::Scores::DataType::Numeric,
        comment: 'Test comment',
        trace_id: 'trace-123',
        observation_id: 'span-456'
      )

      payload = event.to_langfuse_payload

      expect(payload).to eq({
        id: 'score-id-123',
        name: 'accuracy',
        value: 0.95,
        dataType: 'NUMERIC',
        comment: 'Test comment',
        traceId: 'trace-123',
        observationId: 'span-456'
      })
    end

    it 'omits nil optional fields' do
      event = described_class.new(
        name: 'accuracy',
        value: 0.95,
        trace_id: 'trace-123'
      )

      payload = event.to_langfuse_payload

      expect(payload).not_to have_key(:comment)
      expect(payload).not_to have_key(:observationId)
      expect(payload[:traceId]).to eq('trace-123')
    end

    it 'serializes boolean data type correctly' do
      event = described_class.new(
        name: 'is_correct',
        value: 1,
        data_type: DSPy::Scores::DataType::Boolean,
        trace_id: 'trace-123'
      )

      payload = event.to_langfuse_payload

      expect(payload[:dataType]).to eq('BOOLEAN')
      expect(payload[:value]).to eq(1)
    end

    it 'serializes categorical data type correctly' do
      event = described_class.new(
        name: 'category',
        value: 'helpful',
        data_type: DSPy::Scores::DataType::Categorical,
        trace_id: 'trace-123'
      )

      payload = event.to_langfuse_payload

      expect(payload[:dataType]).to eq('CATEGORICAL')
      expect(payload[:value]).to eq('helpful')
    end
  end
end

RSpec.describe DSPy::Scores::DataType do
  describe 'enum values' do
    it 'has Numeric type' do
      expect(DSPy::Scores::DataType::Numeric.serialize).to eq('NUMERIC')
    end

    it 'has Boolean type' do
      expect(DSPy::Scores::DataType::Boolean.serialize).to eq('BOOLEAN')
    end

    it 'has Categorical type' do
      expect(DSPy::Scores::DataType::Categorical.serialize).to eq('CATEGORICAL')
    end
  end
end
