# frozen_string_literal: true

require 'spec_helper'
require 'gepa/telemetry'

RSpec.describe GEPA::Telemetry do
  describe '.with_span' do
    it 'prefixes the operation and merges default attributes' do
      captured = {}

      allow(DSPy::Context).to receive(:with_span) do |operation:, **attrs, &block|
        captured[:operation] = operation
        captured[:attrs] = attrs
        block ? block.call : nil
      end

      result = described_class.with_span('engine.iteration', iteration: 3) { :ok }

      expect(result).to eq(:ok)
      expect(captured[:operation]).to eq('gepa.engine.iteration')
      expect(captured[:attrs]).to include(:optimizer => 'GEPA', :iteration => 3)
      expect(captured[:attrs]).to include(:'gepa.instrumentation_version' => 'phase0')
    end

    it 'does not double-prefix operations that already include gepa.' do
      captured = {}

      allow(DSPy::Context).to receive(:with_span) do |operation:, **attrs, &block|
        captured[:operation] = operation
        captured[:attrs] = attrs
        block&.call
      end

      described_class.with_span('gepa.proposer.select_candidate') {}

      expect(captured[:operation]).to eq('gepa.proposer.select_candidate')
    end
  end

  describe '.emit' do
    it 'prefixes the event name and merges default attributes' do
      captured = {}

      allow(DSPy).to receive(:log) do |event_name, **attrs|
        captured[:event] = event_name
        captured[:attrs] = attrs
      end

      described_class.emit('engine.loop', iteration: 4)

      expect(captured[:event]).to eq('gepa.engine.loop')
      expect(captured[:attrs]).to include(:optimizer => 'GEPA', :iteration => 4)
    end
  end

  describe '.build_context' do
    it 'creates a context with shared attributes and unique run id' do
      context = described_class.build_context(environment: 'test')

      expect(context).to be_a(GEPA::Telemetry::Context)
      expect(context.run_id).to be_a(String)

      span_data = {}
      allow(DSPy::Context).to receive(:with_span) do |operation:, **attrs, &block|
        span_data[:operation] = operation
        span_data[:attrs] = attrs
        block ? block.call : nil
      end

      result = context.with_span('engine.iteration', iteration: 2) { :done }

      expect(result).to eq(:done)
      expect(span_data[:attrs]).to include(:environment => 'test', :run_id => context.run_id)

      log_data = {}
      allow(DSPy).to receive(:log) do |event_name, **attrs|
        log_data[:event] = event_name
        log_data[:attrs] = attrs
      end

      context.emit('proposer.candidate', candidate_id: 'abc123')

      expect(log_data[:event]).to eq('gepa.proposer.candidate')
      expect(log_data[:attrs]).to include(:candidate_id => 'abc123', :run_id => context.run_id)
    end
  end
end

