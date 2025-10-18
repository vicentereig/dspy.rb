# frozen_string_literal: true

require 'spec_helper'
require 'gepa'

RSpec.describe GEPA::Logging::ExperimentTracker do
  it 'records metrics and exposes them via events' do
    tracker = described_class.new
    tracker.log_metrics({ accuracy: 0.4 }, step: 1)

    expect(tracker.events).to eq([{ metrics: { accuracy: 0.4 }, step: 1 }])
    expect(tracker).to be_active
  end

  it 'notifies subscribers and swallows errors' do
    received = []
    tracker = described_class.new(subscribers: [proc { |event| received << event[:metrics] }, proc { |_event| raise 'boom' }])

    tracker.log_metrics({ loss: 0.1 }, step: 7)

    expect(received).to eq([{ loss: 0.1 }])
    expect(tracker.events.first[:step]).to eq(7)
  end
end

