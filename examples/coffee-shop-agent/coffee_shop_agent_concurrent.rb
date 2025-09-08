#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dspy'
require 'async'
require 'async/barrier'

# Load .env from project root
require 'dotenv'
Dotenv.load(File.join(File.dirname(__FILE__), '..', '..', '.env'))

# Initialize New Relic monitoring
require 'newrelic_rpm'
NewRelic::Agent.manual_start

# Configure DSPy
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    ENV.fetch('ANTHROPIC_MODEL', 'anthropic/claude-3-5-sonnet-20241022'),
    api_key: ENV['ANTHROPIC_API_KEY']
  )
end

# Configure observability for Langfuse tracing
DSPy::Observability.configure!

# Define enums for better type safety
class DrinkSize < T::Enum
  enums do
    Small = new('small')
    Medium = new('medium')
    Large = new('large')
  end
end

class Urgency < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
  end
end

class CustomerMood < T::Enum
  enums do
    Happy = new('happy')
    Neutral = new('neutral')
    Upset = new('upset')
  end
end

class TimeOfDay < T::Enum
  enums do
    Morning = new('morning')
    Afternoon = new('afternoon')
    Evening = new('evening')
    RushHour = new('rush_hour')
  end
end

# Our agent can take different actions
module CoffeeShopActions
  class MakeDrink < T::Struct
    const :drink_type, String
    const :size, DrinkSize
    const :customizations, T::Array[String]
  end
  
  class RefundOrder < T::Struct
    const :order_id, String
    const :reason, String
    const :refund_amount, Float
  end
  
  class CallManager < T::Struct
    const :issue, String
    const :urgency, Urgency
  end
  
  class Joke < T::Struct
    const :setup, String
    const :punchline, String
  end
end

# The single signature that handles everything with union types
class CoffeeShopSignature < DSPy::Signature
  description "Analyze customer request and take appropriate action"
  
  input do
    const :customer_request, String
    const :customer_mood, CustomerMood
    const :time_of_day, TimeOfDay
  end
  
  output do
    const :action, T.any(      # Single union field - no discriminator needed!
      CoffeeShopActions::MakeDrink,
      CoffeeShopActions::RefundOrder,
      CoffeeShopActions::CallManager,
      CoffeeShopActions::Joke
    )
    const :friendly_response, String
  end
end

# The actual agent - much simpler with single-field unions!
class CoffeeShopAgent < DSPy::Module
  def initialize
    super()
    # Use ChainOfThought for better reasoning
    @decision_maker = DSPy::ChainOfThought.new(CoffeeShopSignature)
  end
  
  def handle_customer(request:, mood: CustomerMood::Neutral, time: TimeOfDay::Afternoon, customer_id: nil)
    start_time = Time.now
    puts "🚀 [Customer #{customer_id}] Starting request at #{start_time.strftime('%H:%M:%S.%L')}"
    
    # One call handles everything!
    result = @decision_maker.call(
      customer_request: request,
      customer_mood: mood,
      time_of_day: time
    )
    
    puts "🧠 [Customer #{customer_id}] Reasoning: #{result.reasoning}"
    
    # Pattern match on the automatically-typed action
    puts "\n☕ [Customer #{customer_id}] Taking action..."
    case result.action
    when CoffeeShopActions::MakeDrink
      puts "[Customer #{customer_id}] Making a #{result.action.size.serialize} #{result.action.drink_type}"
      puts "[Customer #{customer_id}] Customizations: #{result.action.customizations.join(', ')}" unless result.action.customizations.empty?
    when CoffeeShopActions::RefundOrder
      puts "[Customer #{customer_id}] Processing refund of $#{'%.2f' % result.action.refund_amount}"
      puts "[Customer #{customer_id}] Reason: #{result.action.reason}"
    when CoffeeShopActions::CallManager
      puts "[Customer #{customer_id}] 📞 Calling manager about: #{result.action.issue}"
      puts "[Customer #{customer_id}] Urgency: #{result.action.urgency.serialize}"
    when CoffeeShopActions::Joke
      puts "[Customer #{customer_id}] 😄 #{result.action.setup}"
      puts "[Customer #{customer_id}] 😂 #{result.action.punchline}"
    end
    
    puts "\n💬 [Customer #{customer_id}] Response: #{result.friendly_response}"
    
    end_time = Time.now
    duration = ((end_time - start_time) * 1000).round(1)
    puts "⏱️  [Customer #{customer_id}] Completed in #{duration}ms"
    puts "\n" + "="*60 + "\n"
  end
end

# Main execution with concurrent processing
if __FILE__ == $0
  # Check for API key
  unless ENV['ANTHROPIC_API_KEY'] || ENV['OPENAI_API_KEY']
    puts "Error: Please set ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable"
    exit 1
  end
  
  # Configure for OpenAI if no Anthropic key
  if !ENV['ANTHROPIC_API_KEY'] && ENV['OPENAI_API_KEY']
    DSPy.configure do |config|
      config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end
  
  # Concurrent processing with Async reactor
  puts "Welcome to the AI Coffee Shop! 🤖☕ (Concurrent Version)"
  puts "Processing all customers concurrently...\n\n"
  
  total_start = Time.now
  
  Async do
    agent = CoffeeShopAgent.new
    barrier = Async::Barrier.new
    
    # Launch all customer requests concurrently
    puts "🚀 Launching all customer requests concurrently at #{total_start.strftime('%H:%M:%S.%L')}\n\n"
    
    # Happy customer
    barrier.async do
      agent.handle_customer(
        request: "Can I get a large iced latte with oat milk and an extra shot?",
        mood: CustomerMood::Happy,
        time: TimeOfDay::Morning,
        customer_id: 1
      )
    end
    
    # Upset customer
    barrier.async do
      agent.handle_customer(
        request: "This coffee tastes terrible and I waited 20 minutes!",
        mood: CustomerMood::Upset,
        time: TimeOfDay::RushHour,
        customer_id: 2
      )
    end
    
    # Confused customer
    barrier.async do
      agent.handle_customer(
        request: "Do you sell hamburgers?",
        mood: CustomerMood::Neutral,
        time: TimeOfDay::Afternoon,
        customer_id: 3
      )
    end
    
    # Friendly customer
    barrier.async do
      agent.handle_customer(
        request: "It's been a long day... got any coffee jokes?",
        mood: CustomerMood::Happy,
        time: TimeOfDay::Evening,
        customer_id: 4
      )
    end
    
    # Wait for all customers to be served
    puts "⏳ Waiting for all customer requests to complete...\n"
    barrier.wait
    
    total_end = Time.now
    total_duration = ((total_end - total_start) * 1000).round(1)
    
    puts "\n🎉 All customers served!"
    puts "⚡ Total execution time: #{total_duration}ms"
    puts "💡 Compare this to sequential execution time!"
    
    # Flush observability data before process exits
    DSPy::Observability.flush!
  end
end