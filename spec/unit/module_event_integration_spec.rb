# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy Module Event Integration' do
  after do
    DSPy.events.clear_listeners
  end

  it 'verifies that existing DSPy.log calls in modules now emit events' do
    # Create a simple event listener to capture module events
    received_events = []
    
    DSPy.events.subscribe('*') do |event_name, attributes|
      received_events << [event_name, attributes]
    end
    
    # Test that DSPy.log calls (which modules use) now trigger event listeners
    DSPy.log('chain_of_thought.reasoning_complete', 
      signature_name: 'TestSignature',
      reasoning_steps: 3,
      duration_ms: 500
    )
    
    DSPy.log('react.iteration_complete',
      iteration: 2,
      thought: 'Testing thought',
      action: 'search',
      observation: 'Found results'
    )
    
    DSPy.log('codeact.iteration_complete',
      iteration: 1,
      code_generated: 'puts "hello"',
      execution_result: 'hello'
    )
    
    # Verify events were captured
    expect(received_events.length).to eq(3)
    
    event_names = received_events.map { |e| e[0] }
    expect(event_names).to include(
      'chain_of_thought.reasoning_complete',
      'react.iteration_complete', 
      'codeact.iteration_complete'
    )
    
    # Check that attributes are properly passed through
    cot_event = received_events.find { |e| e[0] == 'chain_of_thought.reasoning_complete' }
    expect(cot_event[1][:signature_name]).to eq('TestSignature')
    expect(cot_event[1][:reasoning_steps]).to eq(3)
  end
  
  it 'demonstrates custom subscriber for module events' do
    # Example: Custom subscriber that tracks module performance
    class ModulePerformanceTracker < DSPy::Events::BaseSubscriber
      attr_reader :module_stats
      
      def initialize
        super
        @module_stats = Hash.new { |h, k| h[k] = { total_calls: 0, total_duration: 0, avg_duration: 0 } }
        subscribe
      end
      
      def subscribe
        # Listen to all module completion events
        add_subscription('*.complete') do |event_name, attributes|
          module_name = event_name.split('.').first
          duration = attributes[:duration_ms] || 0
          
          stats = @module_stats[module_name]
          stats[:total_calls] += 1
          stats[:total_duration] += duration
          stats[:avg_duration] = stats[:total_duration] / stats[:total_calls].to_f
        end
      end
    end
    
    tracker = ModulePerformanceTracker.new
    
    # Simulate module events (these would normally come from actual module execution)
    DSPy.event('chain_of_thought.complete', duration_ms: 500)
    DSPy.event('chain_of_thought.complete', duration_ms: 700)
    DSPy.event('react.complete', duration_ms: 1200)
    DSPy.event('codeact.complete', duration_ms: 800)
    
    # Check tracking results
    expect(tracker.module_stats['chain_of_thought'][:total_calls]).to eq(2)
    expect(tracker.module_stats['chain_of_thought'][:avg_duration]).to eq(600.0)
    expect(tracker.module_stats['react'][:total_calls]).to eq(1)
    expect(tracker.module_stats['react'][:avg_duration]).to eq(1200.0)
    
    tracker.unsubscribe
  end
  
  it 'shows how to track signature usage across modules' do
    # Example: Track which signatures are being used most
    class SignatureUsageTracker < DSPy::Events::BaseSubscriber
      attr_reader :signature_counts
      
      def initialize
        super
        @signature_counts = Hash.new(0)
        subscribe
      end
      
      def subscribe
        add_subscription('*') do |event_name, attributes|
          if attributes[:signature_name]
            @signature_counts[attributes[:signature_name]] += 1
          end
        end
      end
    end
    
    tracker = SignatureUsageTracker.new
    
    # Simulate events with signature names (as modules would emit)
    DSPy.event('module.forward', signature_name: 'QuestionAnswering')
    DSPy.event('chain_of_thought.complete', signature_name: 'QuestionAnswering')
    DSPy.event('module.forward', signature_name: 'SentimentAnalysis')
    DSPy.event('react.complete', signature_name: 'QuestionAnswering')
    
    expect(tracker.signature_counts['QuestionAnswering']).to eq(3)
    expect(tracker.signature_counts['SentimentAnalysis']).to eq(1)
    
    tracker.unsubscribe
  end
end