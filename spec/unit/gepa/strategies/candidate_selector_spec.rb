# frozen_string_literal: true

require 'spec_helper'
require 'gepa'
require 'gepa/strategies/candidate_selector'

RSpec.describe GEPA::Strategies::ParetoCandidateSelector do
  let(:telemetry) { instance_double('Telemetry') }

  it 'selects candidate using pareto sampling with instrumentation' do
    selector = described_class.new(rng: Random.new(0), telemetry: telemetry)

    expect(telemetry).to receive(:with_span) do |operation, attrs, &block|
      expect(operation).to eq('gepa.strategies.candidate_selector')
      expect(attrs[:strategy]).to eq('pareto')
      block.call
    end

    state = GEPA::Core::State.new({ 'instruction' => 'initial' }, [['out'], [0.4]])
    state.update_state_with_new_program([0], { 'instruction' => 'improved' }, 0.8, ['out'], [0.8], nil, 0)

    expect(selector.select_candidate_idx(state)).to eq(1)
  end
end

RSpec.describe GEPA::Strategies::CurrentBestCandidateSelector do
  let(:telemetry) { instance_double('Telemetry') }

  it 'selects the index with best score and emits telemetry span' do
    selector = described_class.new(telemetry: telemetry)

    expect(telemetry).to receive(:with_span) do |operation, attrs, &block|
      expect(operation).to eq('gepa.strategies.candidate_selector')
      expect(attrs[:strategy]).to eq('current_best')
      block.call
    end

    state = GEPA::Core::State.new({ 'instruction' => 'initial' }, [['out'], [0.3]])
    state.update_state_with_new_program([0], { 'instruction' => 'better' }, 0.6, ['out'], [0.6], nil, 0)

    expect(selector.select_candidate_idx(state)).to eq(1)
  end
end
