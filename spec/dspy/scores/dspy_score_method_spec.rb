# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy.score' do
  before do
    # Clear context between tests
    DSPy::Context.clear!
  end

  describe 'basic usage' do
    it 'creates a score event with name and value' do
      event = DSPy.score('accuracy', 0.95)

      expect(event).to be_a(DSPy::Scores::ScoreEvent)
      expect(event.name).to eq('accuracy')
      expect(event.value).to eq(0.95)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Numeric)
    end

    it 'creates a score event with comment' do
      event = DSPy.score('accuracy', 0.95, comment: 'Exact match')

      expect(event.comment).to eq('Exact match')
    end

    it 'creates a score event with boolean data type' do
      event = DSPy.score('is_valid', 1, data_type: :boolean)

      expect(event.data_type).to eq(DSPy::Scores::DataType::Boolean)
      expect(event.value).to eq(1)
    end

    it 'creates a score event with categorical data type' do
      event = DSPy.score('sentiment', 'positive', data_type: :categorical)

      expect(event.data_type).to eq(DSPy::Scores::DataType::Categorical)
      expect(event.value).to eq('positive')
    end
  end

  describe 'context integration' do
    it 'automatically extracts trace_id from DSPy::Context' do
      # Access context to initialize it with a trace_id
      trace_id = DSPy::Context.current[:trace_id]

      event = DSPy.score('accuracy', 0.95)

      expect(event.trace_id).to eq(trace_id)
    end

    it 'allows explicit trace_id override' do
      event = DSPy.score('accuracy', 0.95, trace_id: 'custom-trace-123')

      expect(event.trace_id).to eq('custom-trace-123')
    end

    it 'allows explicit observation_id' do
      event = DSPy.score('accuracy', 0.95, observation_id: 'span-456')

      expect(event.observation_id).to eq('span-456')
    end
  end

  describe 'event emission' do
    it 'emits score.create event to the event registry' do
      events_received = []
      subscription_id = DSPy.events.subscribe('score.create') do |name, attrs|
        events_received << { name: name, attrs: attrs }
      end

      DSPy.score('accuracy', 0.95, comment: 'Test score')

      expect(events_received.length).to eq(1)
      expect(events_received.first[:name]).to eq('score.create')
      expect(events_received.first[:attrs][:score_name]).to eq('accuracy')
      expect(events_received.first[:attrs][:score_value]).to eq(0.95)

      DSPy.events.unsubscribe(subscription_id)
    end
  end

  describe 'symbol to DataType conversion' do
    it 'converts :numeric symbol to DataType::Numeric' do
      event = DSPy.score('test', 0.5, data_type: :numeric)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Numeric)
    end

    it 'converts :boolean symbol to DataType::Boolean' do
      event = DSPy.score('test', 1, data_type: :boolean)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Boolean)
    end

    it 'converts :categorical symbol to DataType::Categorical' do
      event = DSPy.score('test', 'value', data_type: :categorical)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Categorical)
    end

    it 'accepts DataType enum directly' do
      event = DSPy.score('test', 0.5, data_type: DSPy::Scores::DataType::Numeric)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Numeric)
    end
  end

  describe 'DSPy::Scores.create' do
    it 'is an alias for DSPy.score' do
      event = DSPy::Scores.create(name: 'accuracy', value: 0.95)

      expect(event).to be_a(DSPy::Scores::ScoreEvent)
      expect(event.name).to eq('accuracy')
      expect(event.value).to eq(0.95)
    end
  end
end
