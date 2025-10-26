# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Module-scoped listeners' do
  before do
    DSPy.events.clear_listeners
  end

  after do
    DSPy.events.clear_listeners
  end

  class TestEmitterModule < DSPy::Module
    def forward(origin:)
      DSPy.event('module_scoped.test', origin: origin)
    end
  end

  class TestListenerModule < DSPy::Module
    subscribe 'module_scoped.test', :record_event

    attr_reader :recorded, :child

    def initialize(child: TestEmitterModule.new)
      super()
      @recorded = []
      @child = child
    end

    def record_event(event_name, attributes)
      @recorded << {
        event: event_name,
        origin: attributes[:origin],
        module_path: attributes[:module_path],
        module_scope: attributes[:module_scope]
      }
    end

    def forward
      DSPy.event('module_scoped.test', origin: :parent)
      child.call(origin: :child)
      recorded
    end
  end

  class SelfScopedModule < DSPy::Module
    subscribe 'module_scoped.test', :record_event, scope: DSPy::Module::SubcriptionScope::SelfOnly

    attr_reader :recorded, :child

    def initialize(child: TestEmitterModule.new)
      super()
      @recorded = []
      @child = child
    end

    def record_event(_event_name, attributes)
      @recorded << attributes[:origin]
    end

    def forward
      DSPy.event('module_scoped.test', origin: :self)
      child.call(origin: :child)
      recorded
    end
  end

  describe 'descendant scope' do
    it 'captures events from the module and its descendants only' do
      parent = TestListenerModule.new
      sibling = TestListenerModule.new

      parent.call
      sibling.child.call(origin: :isolated) # should not affect parent

      expect(parent.recorded.map { |entry| entry[:origin] }).to eq([:parent, :child])
      expect(sibling.recorded).to be_empty

      parent.recorded.each do |entry|
        path = entry.fetch(:module_path)
        expect(path.first[:class]).to eq('TestListenerModule')
        expect(path.last[:class]).to eq(entry[:origin] == :parent ? 'TestListenerModule' : 'TestEmitterModule')
        expect(entry.fetch(:module_scope)).to include(:ancestry_token, :depth)
      end
    end
  end

  describe 'self scope' do
    it 'only fires when the module is the leaf emitter' do
      listener = SelfScopedModule.new
      listener.call

      expect(listener.recorded).to eq([:self])
    end
  end

  describe '#unsubscribe_module_events' do
    it 'stops receiving events until subscriptions are re-established' do
      parent = TestListenerModule.new
      parent.call
      parent.unsubscribe_module_events

      DSPy.event('module_scoped.test', origin: :external)
      expect(parent.recorded.map { |entry| entry[:origin] }).to eq([:parent, :child])

      parent.call
      expect(parent.recorded.map { |entry| entry[:origin] }).to eq([:parent, :child, :parent, :child])
    end
  end
end
