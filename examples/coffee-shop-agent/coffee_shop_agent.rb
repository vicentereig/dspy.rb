#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dspy'

# Configure DSPy
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    ENV.fetch('ANTHROPIC_MODEL', 'anthropic/claude-3-5-sonnet-20241022'),
    api_key: ENV['ANTHROPIC_API_KEY']
  )
end

# Our agent can take different actions
module CoffeeShopActions
  class MakeDrink < T::Struct
    const :drink_type, String
    const :size, T.enum([:small, :medium, :large])
    const :customizations, T::Array[String]
  end
  
  class RefundOrder < T::Struct
    const :order_id, String
    const :reason, String
    const :refund_amount, Float
  end
  
  class CallManager < T::Struct
    const :issue, String
    const :urgency, T.enum([:low, :medium, :high])
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
    const :customer_mood, T.enum([:happy, :neutral, :upset])
    const :time_of_day, String
  end
  
  output do
    const :action, T.any(      # Single union field - no discriminator needed!
      CoffeeShopActions::MakeDrink,
      CoffeeShopActions::RefundOrder,
      CoffeeShopActions::CallManager,
      CoffeeShopActions::Joke
    )
    const :reasoning, String
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
  
  def handle_customer(request:, mood: :neutral, time: "afternoon")
    # One call handles everything!
    result = @decision_maker.call(
      customer_request: request,
      customer_mood: mood,
      time_of_day: time
    )
    
    puts "🧠 Reasoning: #{result.reasoning}"
    
    # Pattern match on the automatically-typed action
    puts "\n☕ Taking action..."
    case result.action
    when CoffeeShopActions::MakeDrink
      puts "Making a #{result.action.size} #{result.action.drink_type}"
      puts "Customizations: #{result.action.customizations.join(', ')}" unless result.action.customizations.empty?
    when CoffeeShopActions::RefundOrder
      puts "Processing refund of $#{'%.2f' % result.action.refund_amount}"
      puts "Reason: #{result.action.reason}"
    when CoffeeShopActions::CallManager
      puts "📞 Calling manager about: #{result.action.issue}"
      puts "Urgency: #{result.action.urgency}"
    when CoffeeShopActions::Joke
      puts "😄 #{result.action.setup}"
      puts "😂 #{result.action.punchline}"
    end
    
    puts "\n💬 Response to customer: #{result.friendly_response}"
    puts "\n" + "="*60 + "\n"
  end
end

# Main execution
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
  
  # Let's see it in action!
  agent = CoffeeShopAgent.new
  
  puts "Welcome to the AI Coffee Shop! 🤖☕\n\n"
  
  # Happy customer
  agent.handle_customer(
    request: "Can I get a large iced latte with oat milk and an extra shot?",
    mood: :happy,
    time: "morning"
  )
  
  # Upset customer
  agent.handle_customer(
    request: "This coffee tastes terrible and I waited 20 minutes!",
    mood: :upset,
    time: "rush_hour"
  )
  
  # Confused customer
  agent.handle_customer(
    request: "Do you sell hamburgers?",
    mood: :neutral,
    time: "afternoon"
  )
  
  # Friendly customer
  agent.handle_customer(
    request: "It's been a long day... got any coffee jokes?",
    mood: :happy,
    time: "evening"
  )
end