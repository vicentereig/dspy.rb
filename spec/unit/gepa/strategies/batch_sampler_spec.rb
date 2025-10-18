# frozen_string_literal: true

require 'spec_helper'
require 'gepa'
require 'gepa/strategies/batch_sampler'

RSpec.describe GEPA::Strategies::EpochShuffledBatchSampler do
  let(:telemetry) { instance_double('Telemetry') }

  it 'shuffles deterministically per epoch and emits telemetry' do
    sampler = described_class.new(2, rng: Random.new(0), telemetry: telemetry)

    expect(telemetry).to receive(:with_span) do |operation, attrs, &block|
      expect(operation).to eq('gepa.strategies.batch_sampler')
      expect(attrs[:minibatch_size]).to eq(2)
      expect(attrs[:iteration]).to eq(0)
      block.call
    end

    indices = sampler.next_minibatch_indices(3, 0)
    expect(indices.length).to eq(2)

    # Next iteration uses cached shuffle - still deterministic but advanced window
    allow(telemetry).to receive(:with_span) { |_operation, _attrs, &block| block.call }
    second_indices = sampler.next_minibatch_indices(3, 1)

    expect(second_indices.length).to eq(2)
    expect(indices).not_to eq(second_indices)
  end
end
