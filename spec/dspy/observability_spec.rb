# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Observability do
  describe '.configure!' do
    context 'when Langfuse env vars are present' do
      before do
        ENV['LANGFUSE_PUBLIC_KEY'] = 'pk-lf-test-12345'
        ENV['LANGFUSE_SECRET_KEY'] = 'sk-lf-test-67890'
        ENV['LANGFUSE_HOST'] = 'https://test.langfuse.com'
      end

      after do
        ENV.delete('LANGFUSE_PUBLIC_KEY')
        ENV.delete('LANGFUSE_SECRET_KEY') 
        ENV.delete('LANGFUSE_HOST')
        described_class.reset!
      end

      it 'configures OpenTelemetry with OTLP exporter' do
        expect { described_class.configure! }.not_to raise_error
        expect(described_class.enabled?).to be true
        expect(described_class.endpoint).to eq('https://test.langfuse.com/api/public/otel')
      end

      it 'uses default Langfuse cloud endpoint when LANGFUSE_HOST not set' do
        ENV.delete('LANGFUSE_HOST')
        described_class.configure!
        expect(described_class.endpoint).to eq('https://cloud.langfuse.com/api/public/otel')
      end
    end

    context 'when Langfuse env vars are missing' do
      before do
        ENV.delete('LANGFUSE_PUBLIC_KEY')
        ENV.delete('LANGFUSE_SECRET_KEY')
      end

      it 'does not configure OpenTelemetry' do
        described_class.configure!
        expect(described_class.enabled?).to be false
      end
    end

    context 'when OpenTelemetry gems are missing' do
      before do
        ENV['LANGFUSE_PUBLIC_KEY'] = 'pk-lf-test'
        ENV['LANGFUSE_SECRET_KEY'] = 'sk-lf-test'
        allow(described_class).to receive(:require).and_raise(LoadError)
      end

      after do
        ENV.delete('LANGFUSE_PUBLIC_KEY')
        ENV.delete('LANGFUSE_SECRET_KEY')
        described_class.reset!
      end

      it 'gracefully disables observability' do
        expect(DSPy).to receive(:log).with('observability.disabled', reason: 'OpenTelemetry gems not available')
        described_class.configure!
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe '.tracer' do
    context 'when enabled' do
      before do
        ENV['LANGFUSE_PUBLIC_KEY'] = 'pk-lf-test'
        ENV['LANGFUSE_SECRET_KEY'] = 'sk-lf-test'
        described_class.configure!
      end

      after do
        ENV.delete('LANGFUSE_PUBLIC_KEY')
        ENV.delete('LANGFUSE_SECRET_KEY')
        described_class.reset!
      end

      it 'returns OpenTelemetry tracer' do
        tracer = described_class.tracer
        expect(tracer).to respond_to(:start_span)
        expect(tracer).to respond_to(:in_span)
      end
    end

    context 'when disabled' do
      before { described_class.reset! }

      it 'returns nil' do
        expect(described_class.tracer).to be_nil
      end
    end
  end

  describe '.start_span' do
    context 'when enabled' do
      let(:mock_tracer) { double('tracer') }
      let(:mock_span) { double('span') }

      before do
        ENV['LANGFUSE_PUBLIC_KEY'] = 'pk-lf-test'
        ENV['LANGFUSE_SECRET_KEY'] = 'sk-lf-test'
        described_class.configure!
        allow(described_class).to receive(:tracer).and_return(mock_tracer)
      end

      after do
        ENV.delete('LANGFUSE_PUBLIC_KEY')
        ENV.delete('LANGFUSE_SECRET_KEY')
        described_class.reset!
      end

      it 'creates OpenTelemetry span with correct attributes' do
        expect(mock_tracer).to receive(:start_span).with(
          'test.operation',
          hash_including(
            kind: :internal,
            attributes: hash_including(
              'operation.name' => 'test.operation',
              'custom_attr' => 'value'
            )
          )
        ).and_return(mock_span)

        span = described_class.start_span('test.operation', custom_attr: 'value')
        expect(span).to eq(mock_span)
      end
    end

    context 'when disabled' do
      before { described_class.reset! }

      it 'returns nil' do
        span = described_class.start_span('test.operation')
        expect(span).to be_nil
      end
    end
  end

  describe '.finish_span' do
    let(:mock_span) { double('span') }

    it 'calls finish on the span' do
      expect(mock_span).to receive(:finish)
      described_class.finish_span(mock_span)
    end

    it 'handles nil span gracefully' do
      expect { described_class.finish_span(nil) }.not_to raise_error
    end
  end
end