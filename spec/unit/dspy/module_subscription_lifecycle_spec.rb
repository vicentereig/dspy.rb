# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Module subscription lifecycle' do
  before do
    DSPy.events.clear_listeners
    TestLifecycleListener.reset_events!
  end

  after do
    DSPy.events.clear_listeners
  end

  class TestLifecycleListener < DSPy::Module
    subscribe 'lifecycle.test', :record_event

    class << self
      attr_reader :events

      def reset_events!
        @events = []
      end
    end

    reset_events!

    def record_event(event_name, attributes)
      self.class.events << {
        event: event_name,
        origin: attributes[:origin]
      }
    end

    def forward
      :ok
    end
  end

  it 'removes subscriptions when explicitly unsubscribed' do
    listener = TestLifecycleListener.new

    # Register module-scoped subscriptions.
    listener.call

    listeners = DSPy.events.instance_variable_get(:@listeners)
    expect(listeners.length).to eq(1)

    listener.unsubscribe_module_events

    listeners = DSPy.events.instance_variable_get(:@listeners)
    expect(listeners.length).to eq(0)

    DSPy.event('lifecycle.test', origin: :after_unsubscribe)
    expect(TestLifecycleListener.events).to be_empty
  end

  it 'auto-unsubscribes when the module is garbage collected' do
    listener = TestLifecycleListener.new
    listener.call

    listener = nil
    GC.start

    DSPy.event('lifecycle.test', origin: :after_gc)
    expect(TestLifecycleListener.events).to be_empty
  end
end
