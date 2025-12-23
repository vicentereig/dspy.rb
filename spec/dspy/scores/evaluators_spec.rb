# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Scores::Evaluators do
  before do
    DSPy::Context.clear!
  end

  describe '.exact_match' do
    it 'returns 1.0 for exact match' do
      event = described_class.exact_match(
        output: 'Hello World',
        expected: 'Hello World',
        name: 'exact_test'
      )

      expect(event.value).to eq(1.0)
      expect(event.data_type).to eq(DSPy::Scores::DataType::Numeric)
      expect(event.name).to eq('exact_test')
    end

    it 'returns 0.0 for no match' do
      event = described_class.exact_match(
        output: 'Hello World',
        expected: 'Goodbye World',
        name: 'exact_test'
      )

      expect(event.value).to eq(0.0)
    end

    it 'uses default name if not provided' do
      event = described_class.exact_match(
        output: 'test',
        expected: 'test'
      )

      expect(event.name).to eq('exact_match')
    end

    it 'supports case-insensitive matching' do
      event = described_class.exact_match(
        output: 'Hello World',
        expected: 'hello world',
        ignore_case: true
      )

      expect(event.value).to eq(1.0)
    end
  end

  describe '.contains' do
    it 'returns 1.0 when output contains expected' do
      event = described_class.contains(
        output: 'The quick brown fox jumps',
        expected: 'brown fox',
        name: 'contains_test'
      )

      expect(event.value).to eq(1.0)
    end

    it 'returns 0.0 when output does not contain expected' do
      event = described_class.contains(
        output: 'The quick brown fox jumps',
        expected: 'lazy dog'
      )

      expect(event.value).to eq(0.0)
    end

    it 'supports case-insensitive matching' do
      event = described_class.contains(
        output: 'Hello World',
        expected: 'HELLO',
        ignore_case: true
      )

      expect(event.value).to eq(1.0)
    end

    it 'uses default name' do
      event = described_class.contains(
        output: 'test string',
        expected: 'test'
      )

      expect(event.name).to eq('contains')
    end
  end

  describe '.regex_match' do
    it 'returns 1.0 when output matches regex' do
      event = described_class.regex_match(
        output: 'user@example.com',
        pattern: /\A[\w.+-]+@[\w.-]+\.[a-z]{2,}\z/i,
        name: 'email_format'
      )

      expect(event.value).to eq(1.0)
    end

    it 'returns 0.0 when output does not match regex' do
      event = described_class.regex_match(
        output: 'not-an-email',
        pattern: /\A[\w.+-]+@[\w.-]+\.[a-z]{2,}\z/i
      )

      expect(event.value).to eq(0.0)
    end

    it 'accepts string patterns' do
      event = described_class.regex_match(
        output: 'test123',
        pattern: '\d+'
      )

      expect(event.value).to eq(1.0)
    end

    it 'uses default name' do
      event = described_class.regex_match(
        output: 'test',
        pattern: /test/
      )

      expect(event.name).to eq('regex_match')
    end
  end

  describe '.length_check' do
    it 'returns 1.0 when length is within range' do
      event = described_class.length_check(
        output: 'Hello World',
        min_length: 5,
        max_length: 20,
        name: 'length_test'
      )

      expect(event.value).to eq(1.0)
    end

    it 'returns 0.0 when length is below minimum' do
      event = described_class.length_check(
        output: 'Hi',
        min_length: 5,
        max_length: 20
      )

      expect(event.value).to eq(0.0)
    end

    it 'returns 0.0 when length exceeds maximum' do
      event = described_class.length_check(
        output: 'This is a very long string that exceeds the maximum',
        min_length: 5,
        max_length: 20
      )

      expect(event.value).to eq(0.0)
    end

    it 'works with only min_length' do
      event = described_class.length_check(
        output: 'Hello',
        min_length: 3
      )

      expect(event.value).to eq(1.0)
    end

    it 'works with only max_length' do
      event = described_class.length_check(
        output: 'Hi',
        max_length: 10
      )

      expect(event.value).to eq(1.0)
    end

    it 'uses default name' do
      event = described_class.length_check(
        output: 'test',
        min_length: 1
      )

      expect(event.name).to eq('length_check')
    end
  end

  describe '.similarity' do
    it 'returns 1.0 for identical strings' do
      event = described_class.similarity(
        output: 'Hello World',
        expected: 'Hello World',
        name: 'similarity_test'
      )

      expect(event.value).to eq(1.0)
    end

    it 'returns 0.0 for completely different strings' do
      event = described_class.similarity(
        output: 'abc',
        expected: 'xyz'
      )

      expect(event.value).to eq(0.0)
    end

    it 'returns partial score for similar strings' do
      event = described_class.similarity(
        output: 'Hello World',
        expected: 'Hello Werld'
      )

      expect(event.value).to be > 0.8
      expect(event.value).to be < 1.0
    end

    it 'uses default name' do
      event = described_class.similarity(
        output: 'test',
        expected: 'test'
      )

      expect(event.name).to eq('similarity')
    end
  end

  describe '.json_valid' do
    it 'returns 1.0 for valid JSON' do
      event = described_class.json_valid(
        output: '{"key": "value", "number": 42}',
        name: 'json_test'
      )

      expect(event.value).to eq(1.0)
    end

    it 'returns 0.0 for invalid JSON' do
      event = described_class.json_valid(
        output: '{invalid json}'
      )

      expect(event.value).to eq(0.0)
    end

    it 'returns 1.0 for JSON arrays' do
      event = described_class.json_valid(
        output: '[1, 2, 3]'
      )

      expect(event.value).to eq(1.0)
    end

    it 'uses default name' do
      event = described_class.json_valid(output: '{}')
      expect(event.name).to eq('json_valid')
    end
  end

  describe 'event emission' do
    it 'emits score.create events by default' do
      events = []
      subscription_id = DSPy.events.subscribe('score.create') do |name, attrs|
        events << attrs
      end

      described_class.exact_match(output: 'test', expected: 'test')

      expect(events.length).to eq(1)
      expect(events.first[:score_name]).to eq('exact_match')

      DSPy.events.unsubscribe(subscription_id)
    end

    it 'respects emit: false option' do
      events = []
      subscription_id = DSPy.events.subscribe('score.create') do |name, attrs|
        events << attrs
      end

      described_class.exact_match(output: 'test', expected: 'test', emit: false)

      expect(events).to be_empty

      DSPy.events.unsubscribe(subscription_id)
    end
  end

  describe 'context propagation' do
    it 'inherits trace_id from context' do
      trace_id = DSPy::Context.current[:trace_id]

      event = described_class.exact_match(output: 'test', expected: 'test')

      expect(event.trace_id).to eq(trace_id)
    end

    it 'allows explicit trace_id override' do
      event = described_class.exact_match(
        output: 'test',
        expected: 'test',
        trace_id: 'custom-trace'
      )

      expect(event.trace_id).to eq('custom-trace')
    end
  end
end
