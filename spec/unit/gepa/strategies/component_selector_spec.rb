# frozen_string_literal: true

require 'spec_helper'
require 'gepa'
require 'gepa/strategies/component_selector'

RSpec.describe GEPA::Strategies::RoundRobinReflectionComponentSelector do
  let(:seed_candidate) { { 'instruction' => 'Initial' } }
  let(:state) { GEPA::Core::State.new(seed_candidate, [['out1'], [0.5]]) }
  let(:telemetry) { instance_double('Telemetry') }

  it 'rotates predictor ids and returns selected module name' do
    expect(telemetry).to receive(:with_span) do |operation, attrs, &block|
      expect(operation).to eq('gepa.strategies.component_selector')
      expect(attrs[:strategy]).to eq('round_robin')
      expect(attrs[:candidate_idx]).to eq(0)
      block.call
    end

    selector = described_class.new(telemetry: telemetry)

    expect(
      selector.select_modules(state, [], [], 0, seed_candidate)
    ).to eq(['instruction'])

    expect(state.named_predictor_id_to_update_next_for_program_candidate.first).to eq(0)
  end
end
