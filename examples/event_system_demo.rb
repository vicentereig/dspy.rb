#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/dspy'
require_relative '../spec/support/event_subscriber_examples'

puts "🚀 DSPy.rb OpenTelemetry Event System Demo"
puts "=" * 50
puts

# 1. Basic Event System Demo
puts "1. Basic Event Emission and Listening"
puts "-" * 30

# Set up a simple listener
received_events = []
subscription_id = DSPy.events.subscribe('demo.*') do |event_name, attributes|
  received_events << { name: event_name, data: attributes }
  puts "📡 Event received: #{event_name} with #{attributes.keys.join(', ')}"
end

# Emit some events
DSPy.event('demo.start', message: 'Demo starting!', timestamp: Time.now)
DSPy.event('demo.progress', step: 1, total_steps: 3)
DSPy.event('demo.progress', step: 2, total_steps: 3)

puts "📊 Received #{received_events.length} events"
puts

# 2. Type-Safe Events Demo
puts "2. Type-Safe Event Structures"
puts "-" * 30

# Create type-safe LLM event
llm_event = DSPy::Events::LLMEvent.new(
  name: 'llm.generate',
  provider: 'openai',
  model: 'gpt-4',
  usage: DSPy::Events::TokenUsage.new(
    prompt_tokens: 150,
    completion_tokens: 75
  ),
  duration_ms: 1250,
  temperature: 0.7
)

puts "🎯 Created type-safe LLM event:"
puts "   Provider: #{llm_event.provider}"
puts "   Model: #{llm_event.model}"
puts "   Total tokens: #{llm_event.usage.total_tokens}"
puts "   Duration: #{llm_event.duration_ms}ms"
puts

# Emit the typed event
DSPy.event(llm_event)
puts "✅ Type-safe event emitted successfully"
puts

# 3. Custom Subscriber Demo - Token Tracking Example
puts "3. Custom Token Tracking Subscriber"
puts "-" * 30

# Create a simple token tracker (example implementation)
class SimpleTokenTracker < DSPy::Events::BaseSubscriber
  attr_reader :total_tokens, :request_count
  
  def initialize
    super
    @total_tokens = 0
    @request_count = 0
    subscribe
  end
  
  def subscribe
    add_subscription('llm.*') do |event_name, attributes|
      prompt_tokens = attributes['gen_ai.usage.prompt_tokens'] || 0
      completion_tokens = attributes['gen_ai.usage.completion_tokens'] || 0
      @total_tokens += prompt_tokens + completion_tokens
      @request_count += 1 if prompt_tokens > 0 || completion_tokens > 0
    end
  end
end

token_tracker = SimpleTokenTracker.new
puts "💰 Simple token tracker created"

# Simulate LLM usage with proper OpenTelemetry semantic conventions
3.times do |i|
  DSPy.event('llm.generate', {
    'gen_ai.system' => 'openai',
    'gen_ai.request.model' => 'gpt-4',
    'gen_ai.usage.prompt_tokens' => 100 + (i * 20),
    'gen_ai.usage.completion_tokens' => 50 + (i * 10),
    'duration_ms' => 800 + (i * 100)
  })
  
  puts "📈 After request #{i + 1}: #{token_tracker.total_tokens} tokens used (#{token_tracker.request_count} requests)"
end

puts "💡 Final Token Tracker Summary: #{token_tracker.total_tokens} tokens across #{token_tracker.request_count} requests"
puts

# 4. Custom Subscriber Demo - Optimization Progress Example  
puts "4. Custom Optimization Progress Subscriber"
puts "-" * 30

# Create a simple optimization tracker (example implementation)
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
          score: attributes[:score],
          parameters: attributes[:parameters]
        }
      end
    end
  end
  
  def best_score
    @trials.map { |t| t[:score] }.compact.max
  end
  
  def progress_summary
    "#{@current_optimizer}: #{@trials.length} trials, best score: #{best_score&.round(4) || 'N/A'}"
  end
end

optimizer_tracker = SimpleOptimizationTracker.new
puts "📋 Simple optimization tracker created"

# Simulate an optimization session
DSPy.event('optimization.start', optimizer_name: 'MIPROv2')
puts "🏁 Starting optimization with MIPROv2"

# Simulate trials with improving scores
5.times do |i|
  score = 0.65 + (i * 0.04) + (rand * 0.02) # Gradually improving with noise
  DSPy.event('optimization.trial_complete', {
    optimizer_name: 'MIPROv2',
    trial_number: i + 1,
    score: score.round(4),
    parameters: {
      temperature: 0.9 - (i * 0.1),
      max_tokens: 100 + (i * 20)
    }
  })
  
  puts "🎯 #{optimizer_tracker.progress_summary}"
end

DSPy.event('optimization.complete', optimizer_name: 'MIPROv2')
puts "🏆 Optimization complete: #{optimizer_tracker.progress_summary}"
puts

# Bonus: Full-featured optimization reporter example
puts "📄 Generating detailed optimization report..."
full_reporter = EventSubscriberExamples::OptimizationReporter.new(
  output_path: File.join(__dir__, 'demo_optimization_report.md'),
  auto_write: false
)

# Re-run the optimization to generate a full report
DSPy.event('optimization.start', optimizer_name: 'DetailedMIPROv2')
5.times do |i|
  score = 0.65 + (i * 0.04) + (rand * 0.02)
  DSPy.event('optimization.trial_complete', {
    optimizer_name: 'DetailedMIPROv2',
    trial_number: i + 1,
    score: score.round(4),
    best_score: [0.65 + (i * 0.04), score].max.round(4),
    parameters: {
      temperature: 0.9 - (i * 0.1),
      max_tokens: 100 + (i * 20),
      top_p: 0.9 - (i * 0.05)
    },
    duration_ms: 1200 + rand(800)
  })
end
DSPy.event('optimization.complete', optimizer_name: 'DetailedMIPROv2')

report = full_reporter.generate_report
puts "📊 Generated detailed report (#{report.length} characters)"
puts "💾 Saved to: examples/demo_optimization_report.md"

full_reporter.unsubscribe
puts

# 5. Integration Demo: Multiple Subscribers
puts "5. Multiple Subscribers Integration"
puts "-" * 30

# Create a custom subscriber that counts events by type
class EventCounter < DSPy::Events::BaseSubscriber
  attr_reader :counts
  
  def initialize
    super
    @counts = Hash.new(0)
    subscribe
  end
  
  def subscribe
    add_subscription('*') do |event_name, attributes|
      category = event_name.split('.').first
      @counts[category] += 1
    end
  end
end

counter = EventCounter.new
puts "🔢 Event counter subscriber created"

# Emit various events
%w[llm.generate llm.stream module.forward module.complete optimization.trial demo.test].each do |event|
  DSPy.event(event, test_data: true)
end

puts "📊 Event counts by category:"
counter.counts.each { |category, count| puts "   #{category}: #{count}" }
puts

# Clean up
DSPy.events.unsubscribe(subscription_id)
token_tracker.unsubscribe
optimizer_tracker.unsubscribe
counter.unsubscribe

puts "6. Summary"
puts "-" * 30
puts "✨ DSPy.rb OpenTelemetry Event System Demo Complete!"
puts
puts "Key Features Demonstrated:"
puts "• 🎯 Type-safe event structures with Sorbet T::Struct"
puts "• 📡 Pluggable event listener architecture" 
puts "• 💰 Custom token tracking subscribers"
puts "• 📋 Custom optimization progress tracking"
puts "• 🔄 Full backward compatibility with existing DSPy.log calls"
puts "• 🧵 Thread-safe event processing"
puts "• 📈 OpenTelemetry semantic conventions support"
puts
puts "🎉 The event system provides a clean foundation for building"
puts "   custom observability solutions without complex monkey-patching!"

puts "\n" + "=" * 50