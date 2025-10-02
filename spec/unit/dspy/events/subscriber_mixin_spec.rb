# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Events::SubscriberMixin do
  # Test class to demonstrate mixin usage
  class TestSubscriber
    include DSPy::Events::SubscriberMixin
    
    @@received_events = []
    
    def self.received_events
      @@received_events
    end
    
    def self.reset_events!
      @@received_events = []
    end
    
    def self.setup_subscriptions!
      # Set up subscriptions manually for testing
      add_subscription('test.*') do |name, attrs|
        @@received_events << { name: name, attrs: attrs }
      end
      
      add_subscription('llm.response') do |name, attrs|
        @@received_events << { specific: true, name: name, attrs: attrs }
      end
    end
  end

  before do
    TestSubscriber.reset_events!
    TestSubscriber.setup_subscriptions! unless TestSubscriber.subscriptions.any?
  end
  
  after do
    # Clean up subscriptions after each test
    TestSubscriber.unsubscribe_all
  end

  describe 'mixin inclusion' do
    it 'includes the mixin successfully' do
      expect(TestSubscriber.included_modules).to include(described_class)
    end
    
    it 'extends class with ClassMethods' do
      expect(TestSubscriber).to respond_to(:add_subscription)
      expect(TestSubscriber).to respond_to(:unsubscribe_all)
      expect(TestSubscriber).to respond_to(:subscriptions)
    end
  end

  describe 'class-level subscriptions' do
    it 'registers subscriptions with DSPy event system' do
      expect(TestSubscriber.subscriptions).not_to be_empty
      expect(TestSubscriber.subscriptions.size).to eq(2)
    end

    it 'receives events matching patterns' do
      # Emit event that matches 'test.*' pattern
      DSPy.event('test.example', { data: 'hello' })
      
      # Give a moment for async processing if needed
      sleep(0.01)
      
      events = TestSubscriber.received_events
      expect(events).not_to be_empty
      
      matching_event = events.find { |e| e[:name] == 'test.example' }
      expect(matching_event).not_to be_nil
      expect(matching_event[:attrs][:data]).to eq('hello')
    end

    it 'receives multiple events with different patterns' do
      DSPy.event('test.first', { value: 1 })
      DSPy.event('llm.response', { model: 'gpt-4' })
      DSPy.event('test.second', { value: 2 })
      
      sleep(0.01)
      
      events = TestSubscriber.received_events
      expect(events.size).to eq(3) # test.first, test.second match test.*, llm.response matches specific
      
      # Should have received both test.* events
      test_events = events.select { |e| e[:name].start_with?('test.') && !e[:specific] }
      expect(test_events.size).to eq(2)
      
      # Should have received specific llm.response event
      llm_events = events.select { |e| e[:specific] }
      expect(llm_events.size).to eq(1)
      expect(llm_events.first[:attrs][:model]).to eq('gpt-4')
    end

    it 'handles events that dont match any pattern' do
      DSPy.event('unmatched.event', { ignored: true })
      
      sleep(0.01)
      
      expect(TestSubscriber.received_events).to be_empty
    end
  end

  describe '#unsubscribe_all' do
    it 'removes all subscriptions' do
      initial_subscriptions = TestSubscriber.subscriptions.size
      expect(initial_subscriptions).to be > 0
      
      TestSubscriber.unsubscribe_all
      
      # After unsubscribing, events should not be received
      DSPy.event('test.after_unsubscribe', { should_not_receive: true })
      
      sleep(0.01)
      
      expect(TestSubscriber.received_events).to be_empty
    end

    it 'clears the subscriptions list' do
      expect(TestSubscriber.subscriptions).not_to be_empty
      
      TestSubscriber.unsubscribe_all
      
      expect(TestSubscriber.subscriptions).to be_empty
    end
  end

  describe 'thread safety' do
    it 'handles concurrent subscription access safely' do
      threads = []
      
      # Create multiple threads that add subscriptions
      5.times do |i|
        threads << Thread.new do
          TestSubscriber.add_subscription("concurrent.#{i}") do |name, attrs|
            TestSubscriber.received_events << { thread_id: i, name: name }
          end
        end
      end
      
      threads.each(&:join)
      
      # Should have original 2 + 5 new subscriptions  
      expect(TestSubscriber.subscriptions.size).to be >= 7
    end
  end

  describe 'error handling' do
    class ErrorSubscriber
      include DSPy::Events::SubscriberMixin
      
      add_subscription('error.test') do |name, attrs|
        raise StandardError, 'Test error in subscription'
      end
    end

    after do
      ErrorSubscriber.unsubscribe_all
    end

    it 'continues processing other events when one subscription raises error' do
      # This test ensures that errors in one subscription don't break the entire event system
      # The specific behavior depends on DSPy's event system implementation
      
      expect {
        DSPy.event('error.test', { data: 'should cause error' })
        sleep(0.01)
      }.not_to raise_error
      
      # Other subscriptions should still work
      DSPy.event('test.after_error', { data: 'should work' })
      sleep(0.01)
      
      matching_events = TestSubscriber.received_events.select { |e| e[:name] == 'test.after_error' }
      expect(matching_events).not_to be_empty
    end
  end
end