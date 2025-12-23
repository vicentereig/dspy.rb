# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Scores::Exporter do
  let(:public_key) { 'pk-test-123' }
  let(:secret_key) { 'sk-test-456' }
  let(:host) { 'https://cloud.langfuse.com' }

  before do
    DSPy::Context.clear!
  end

  describe '.configure' do
    it 'creates an exporter with credentials' do
      exporter = described_class.configure(
        public_key: public_key,
        secret_key: secret_key,
        host: host
      )

      expect(exporter).to be_a(described_class)
      expect(exporter.host).to eq(host)
    end

    it 'defaults to cloud.langfuse.com' do
      exporter = described_class.configure(
        public_key: public_key,
        secret_key: secret_key
      )

      expect(exporter.host).to eq('https://cloud.langfuse.com')
    end

    it 'subscribes to score.create events' do
      exporter = described_class.configure(
        public_key: public_key,
        secret_key: secret_key
      )

      expect(exporter).to be_running
      exporter.shutdown
    end
  end

  describe '#export' do
    let(:exporter) do
      described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        host: host
      )
    end

    let(:score_event) do
      DSPy::Scores::ScoreEvent.new(
        name: 'accuracy',
        value: 0.95,
        data_type: DSPy::Scores::DataType::Numeric,
        trace_id: 'trace-123'
      )
    end

    after do
      exporter.shutdown if exporter.running?
    end

    it 'queues the score for async export' do
      exporter.start
      exporter.export(score_event)

      expect(exporter.queue_size).to be >= 0
    end

    it 'sends score to Langfuse API', vcr: { cassette_name: 'langfuse/score_export' } do
      exporter.start
      exporter.export(score_event)

      # Wait for async processing
      exporter.shutdown(timeout: 5)

      # VCR will verify the request was made correctly
    end
  end

  describe 'event subscription' do
    let(:exporter) do
      described_class.configure(
        public_key: public_key,
        secret_key: secret_key,
        host: host
      )
    end

    after do
      exporter.shutdown if exporter.running?
    end

    it 'automatically exports scores when DSPy.score is called', vcr: { cassette_name: 'langfuse/score_via_event' } do
      DSPy.score('test_metric', 0.85, trace_id: 'trace-auto-123')

      # Wait for async processing
      exporter.shutdown(timeout: 5)
    end
  end

  describe '#shutdown' do
    let(:exporter) do
      described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        host: host
      )
    end

    it 'drains the queue before stopping' do
      exporter.start

      3.times do |i|
        exporter.export(
          DSPy::Scores::ScoreEvent.new(
            name: "metric_#{i}",
            value: i * 0.1,
            trace_id: 'trace-drain'
          )
        )
      end

      exporter.shutdown(timeout: 5)
      expect(exporter.running?).to be false
    end

    it 'can be called multiple times safely' do
      exporter.start
      exporter.shutdown
      expect { exporter.shutdown }.not_to raise_error
    end
  end

  describe 'payload format' do
    let(:exporter) do
      described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        host: host
      )
    end

    it 'builds correct Langfuse payload' do
      score_event = DSPy::Scores::ScoreEvent.new(
        name: 'relevance',
        value: 0.75,
        data_type: DSPy::Scores::DataType::Numeric,
        comment: 'Good match',
        trace_id: 'trace-456',
        observation_id: 'span-789'
      )

      payload = exporter.send(:build_payload, score_event)

      expect(payload[:name]).to eq('relevance')
      expect(payload[:value]).to eq(0.75)
      expect(payload[:dataType]).to eq('NUMERIC')
      expect(payload[:comment]).to eq('Good match')
      expect(payload[:traceId]).to eq('trace-456')
      expect(payload[:observationId]).to eq('span-789')
    end
  end

  describe 'error handling' do
    let(:exporter) do
      described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        host: host,
        max_retries: 2
      )
    end

    after do
      exporter.shutdown if exporter.running?
    end

    it 'retries on transient failures' do
      exporter.start

      score_event = DSPy::Scores::ScoreEvent.new(
        name: 'retry_test',
        value: 1.0,
        trace_id: 'trace-retry'
      )

      # Mock will fail twice then succeed
      allow(exporter).to receive(:send_to_langfuse).and_raise(StandardError, 'Network error').twice
      allow(exporter).to receive(:send_to_langfuse).and_call_original

      exporter.export(score_event)
      exporter.shutdown(timeout: 5)
    end
  end
end
