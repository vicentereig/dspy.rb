# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Module dup_for_thread' do
  before do
    DSPy.events.clear_listeners
  end

  after do
    DSPy.events.clear_listeners
  end

  class DupListenerModule < DSPy::Module
    subscribe 'dup_for_thread.test', :record_event

    attr_reader :recorded

    def initialize
      super()
      @recorded = []
    end

    def record_event(_event_name, attributes)
      @recorded << attributes[:origin]
    end

    def forward(origin:)
      DSPy.event('dup_for_thread.test', origin: origin)
      recorded
    end

    private

    def reset_thread_state
      super
      @recorded = []
    end
  end

  it 'resets subscriptions and scope for per-thread clones' do
    original = DupListenerModule.new
    original.call(origin: :original)

    listeners = DSPy.events.instance_variable_get(:@listeners)
    expect(listeners.length).to eq(1)

    clone = original.dup_for_thread
    clone.call(origin: :clone)

    listeners = DSPy.events.instance_variable_get(:@listeners)
    expect(listeners.length).to eq(2)

    expect(original.recorded).to eq([:original])
    expect(clone.recorded).to eq([:clone])
  end
end
