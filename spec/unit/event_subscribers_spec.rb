# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Event Subscriber Patterns' do
  after do
    DSPy.events.clear_listeners
  end

  describe DSPy::Events::BaseSubscriber do
    it 'provides foundation for custom subscribers' do
      # Example: Simple event counter
      class TestEventCounter < DSPy::Events::BaseSubscriber
        attr_reader :event_count
        
        def initialize
          super
          @event_count = 0
          subscribe
        end
        
        def subscribe
          add_subscription('test.*') do |event_name, attributes|
            @event_count += 1
          end
        end
      end
      
      counter = TestEventCounter.new
      expect(counter.event_count).to eq(0)
      
      DSPy.event('test.event', data: 'value')
      DSPy.event('test.another', data: 'value')
      DSPy.event('other.event', data: 'ignored')
      
      expect(counter.event_count).to eq(2)
      
      counter.unsubscribe
    end
    
    it 'supports pattern matching in subscriptions' do
      class PatternSubscriber < DSPy::Events::BaseSubscriber
        attr_reader :received_events
        
        def initialize
          super
          @received_events = []
          subscribe
        end
        
        def subscribe
          add_subscription('llm.*') do |event_name, attributes|
            @received_events << event_name
          end
        end
      end
      
      subscriber = PatternSubscriber.new
      
      DSPy.event('llm.generate', provider: 'openai')
      DSPy.event('llm.stream', provider: 'anthropic')
      DSPy.event('module.forward', data: 'ignored')
      DSPy.event('llm.complete', provider: 'google')
      
      expect(subscriber.received_events).to match_array(['llm.generate', 'llm.stream', 'llm.complete'])
      
      subscriber.unsubscribe
    end
    
    it 'handles unsubscription properly' do
      class UnsubscribeTestSubscriber < DSPy::Events::BaseSubscriber
        attr_reader :event_count
        
        def initialize
          super
          @event_count = 0
          subscribe
        end
        
        def subscribe
          add_subscription('test.event') do |event_name, attributes|
            @event_count += 1
          end
        end
      end
      
      subscriber = UnsubscribeTestSubscriber.new
      
      DSPy.event('test.event', data: 'first')
      expect(subscriber.event_count).to eq(1)
      
      subscriber.unsubscribe
      
      DSPy.event('test.event', data: 'second')
      expect(subscriber.event_count).to eq(1) # Should not increment
    end
    
    it 'raises NotImplementedError when subscribe is not overridden' do
      class IncompleteSubscriber < DSPy::Events::BaseSubscriber
        # Missing subscribe implementation
      end
      
      subscriber = IncompleteSubscriber.new
      expect {
        subscriber.subscribe
      }.to raise_error(NotImplementedError, /Subclasses must implement #subscribe/)
    end
  end
  
  describe 'Practical Examples' do
    it 'demonstrates token usage tracking pattern' do
      # Example: Simple token tracker
      class SimpleTokenTracker < DSPy::Events::BaseSubscriber
        attr_reader :total_tokens
        
        def initialize
          super
          @total_tokens = 0
          subscribe
        end
        
        def subscribe
          add_subscription('llm.*') do |event_name, attributes|
            prompt_tokens = attributes['gen_ai.usage.prompt_tokens'] || 0
            completion_tokens = attributes['gen_ai.usage.completion_tokens'] || 0
            @total_tokens += prompt_tokens + completion_tokens
          end
        end
      end
      
      tracker = SimpleTokenTracker.new
      
      DSPy.event('llm.generate', {
        'gen_ai.usage.prompt_tokens' => 100,
        'gen_ai.usage.completion_tokens' => 50
      })
      
      DSPy.event('llm.stream', {
        'gen_ai.usage.prompt_tokens' => 200,
        'gen_ai.usage.completion_tokens' => 75
      })
      
      expect(tracker.total_tokens).to eq(425)
      
      tracker.unsubscribe
    end
    
    it 'demonstrates optimization progress tracking pattern' do
      # Example: Simple optimization tracker
      class SimpleOptimizationTracker < DSPy::Events::BaseSubscriber
        attr_reader :trials, :current_optimizer
        
        def initialize
          super
          @trials = []
          @current_optimizer = nil
          subscribe
        end
        
        def subscribe
          add_subscription('optimization.*') do |event_name, attributes|
            case event_name
            when 'optimization.start'
              @current_optimizer = attributes[:optimizer_name]
              @trials.clear
            when 'optimization.trial_complete'
              @trials << {
                number: attributes[:trial_number],
                score: attributes[:score]
              }
            end
          end
        end
        
        def best_score
          @trials.map { |t| t[:score] }.compact.max
        end
      end
      
      tracker = SimpleOptimizationTracker.new
      
      DSPy.event('optimization.start', optimizer_name: 'TestOptimizer')
      DSPy.event('optimization.trial_complete', trial_number: 1, score: 0.7)
      DSPy.event('optimization.trial_complete', trial_number: 2, score: 0.85)
      DSPy.event('optimization.trial_complete', trial_number: 3, score: 0.92)
      
      expect(tracker.current_optimizer).to eq('TestOptimizer')
      expect(tracker.trials.length).to eq(3)
      expect(tracker.best_score).to eq(0.92)
      
      tracker.unsubscribe
    end
  end
end