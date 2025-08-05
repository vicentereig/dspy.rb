---
layout: blog
name: "Why Union Types Transform AI Agent Development"
date: 2025-07-20
categories: [patterns, agents]
description: How DSPy.rb's single-field union types with automatic type detection simplify AI agent development
toc: true
permalink: /blog/union-types-agentic-workflows/
image:
  path: /assets/images/blog/union-types-agent.jpg
  alt: AI agent workflow with union types
---

Ever built an AI agent that needs to decide between different actions? You know the drill - create a struct with a dozen nilable fields, then play whack-a-mole with nil checks. There's a better way, and DSPy.rb v0.11.0 makes it automatic with single-field union types.

## The Problem: Decision Paralysis in Code Form

Picture this: You're building a coffee shop AI agent that needs to handle various customer requests. The naive approach might look like:

```ruby
# 😱 The horror of nilable everything
class CoffeeShopAction < T::Struct
  # Make drink fields
  const :drink_type, T.nilable(String)
  const :drink_size, T.nilable(String)
  const :customizations, T.nilable(T::Array[String])
  
  # Refund fields
  const :order_id, T.nilable(String)
  const :refund_reason, T.nilable(String)
  const :refund_amount, T.nilable(Float)
  
  # Manager call fields
  const :issue_description, T.nilable(String)
  const :urgency_level, T.nilable(String)
  
  # Joke fields
  const :joke_setup, T.nilable(String)
  const :joke_punchline, T.nilable(String)
  
  # ... and you need to track which action type this is
  const :action_type, String
end
```

This is what I call "struct sprawl" - one struct trying to be everything to everyone. It's the code equivalent of a Swiss Army knife where all the tools fall out when you open it.

## Enter Single-Field Union Types: One Decision, Multiple Paths

Here's the thing about AI agents - they make *one* decision at a time. So why not model it that way?

```ruby
# Each action type gets its own focused struct - no type field needed!
module CoffeeShopActions
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
```

See the difference? Each struct has *only* the fields it needs. No more nil checks. No more "wait, which fields go with which action?" And with DSPy.rb's automatic type detection, you don't even need to define a type field - DSPy handles that for you!

## The Magic: Automatic Type Detection

Here's where DSPy.rb's new single-field union types shine. You just use a single `T.any()` field, and DSPy handles everything:

```ruby
# Define enums for type safety
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
```

Behind the scenes, DSPy automatically:
1. Adds a `_type` field during serialization using the struct's class name
2. Generates JSON schemas with proper constraints for each type
3. Uses the `_type` field to deserialize to the correct struct

When the LLM returns:
```json
{
  "action": {
    "_type": "MakeDrink",
    "drink_type": "iced latte",
    "size": "large",
    "customizations": ["oat milk", "extra shot"]
  },
  "reasoning": "Customer requested a specific coffee drink with customizations",
  "friendly_response": "Coming right up! One large iced latte with oat milk and an extra shot."
}
```

Note: The `reasoning` field is automatically added by ChainOfThought - you don't need to define it in your signature!

DSPy automatically converts it to a `MakeDrink` instance. No manual parsing. No discriminator enums. No type checking. It just works!

## The Coffee Shop Agent in Action

Let's see how this pattern works with a real example. Here's the complete coffee shop agent that demonstrates single-field union types:

```ruby
#!/usr/bin/env ruby
require 'bundler/setup'
require 'dspy'

# Configure DSPy (supports both Anthropic and OpenAI)
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    ENV.fetch('ANTHROPIC_MODEL', 'anthropic/claude-3-5-sonnet-20241022'),
    api_key: ENV['ANTHROPIC_API_KEY']
  )
end

# All enums and action structs defined earlier...
# (Using the same CoffeeShopActions module, enums, and CoffeeShopSignature from above)

# The actual agent - much simpler with single-field unions!
class CoffeeShopAgent < DSPy::Module
  def initialize
    super()
    # Use ChainOfThought for better reasoning
    @decision_maker = DSPy::ChainOfThought.new(CoffeeShopSignature)
  end
  
  def handle_customer(request:, mood: CustomerMood::Neutral, time: TimeOfDay::Afternoon)
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
      puts "Making a #{result.action.size.serialize} #{result.action.drink_type}"
      puts "Customizations: #{result.action.customizations.join(', ')}" unless result.action.customizations.empty?
    when CoffeeShopActions::RefundOrder
      puts "Processing refund of $#{'%.2f' % result.action.refund_amount}"
      puts "Reason: #{result.action.reason}"
    when CoffeeShopActions::CallManager
      puts "📞 Calling manager about: #{result.action.issue}"
      puts "Urgency: #{result.action.urgency.serialize}"
    when CoffeeShopActions::Joke
      puts "😄 #{result.action.setup}"
      puts "😂 #{result.action.punchline}"
    end
    
    puts "\n💬 Response to customer: #{result.friendly_response}"
    puts "\n" + "="*60 + "\n"
  end
end
```

[View the complete source code on GitHub →](https://github.com/vicentereig/dspy.rb/tree/main/examples/coffee-shop-agent)

## Running the Agent

When you run the coffee shop agent, here's what happens:

```ruby
agent = CoffeeShopAgent.new

# Happy customer wanting coffee
agent.handle_customer(
  request: "Can I get a large iced latte with oat milk and an extra shot?",
  mood: CustomerMood::Happy,
  time: TimeOfDay::Morning
)
```

Output:
```
🧠 Reasoning: The customer is in a good mood and requesting a specific coffee 
drink with customizations. I should prepare their order promptly.

☕ Taking action...
Making a large iced latte
Customizations: oat milk, extra shot

💬 Response to customer: Coming right up! One large iced latte with oat milk 
and an extra shot. That'll be ready in about 3 minutes!

============================================================
```

```ruby
# Upset customer with a complaint
agent.handle_customer(
  request: "This coffee tastes terrible and I waited 20 minutes!",
  mood: CustomerMood::Upset,
  time: TimeOfDay::RushHour
)
```

Output:
```
🧠 Reasoning: The customer is upset about both quality and wait time during 
rush hour. This needs immediate manager attention.

☕ Taking action...
📞 Calling manager about: Customer complaint about coffee quality and long wait time
Urgency: high

💬 Response to customer: I'm so sorry about that! Let me get my manager right 
away to help resolve this for you. They'll be here in just a moment.

============================================================
```

```ruby
# Customer needs a laugh
agent.handle_customer(
  request: "It's been a long day... got any coffee jokes?",
  mood: CustomerMood::Happy,
  time: TimeOfDay::Evening
)
```

Output:
```
🧠 Reasoning: The customer seems tired but in good spirits, asking for humor. 
A coffee joke would lighten the mood!

☕ Taking action...
😄 Why did the coffee file a police report?
😂 It got mugged!

💬 Response to customer: Hope that perks you up! We take our humor as 
seriously as our espresso - both are guaranteed to give you a jolt!

============================================================
```

## Why This Matters

### For Developers
- **Type Safety**: Catch errors at development time, not runtime
- **Clear Intent**: Each action type documents itself
- **No Nil Anxiety**: Only deal with fields that actually exist
- **IDE Love**: Autocomplete knows exactly what fields are available

### For Your AI Application
- **Better LLM Performance**: Clear structure helps LLMs generate valid responses
- **Fewer Errors**: Can't accidentally mix fields from different actions
- **Easier Testing**: Each action type can be tested independently
- **Maintainable**: Adding new actions doesn't touch existing code

## The Pattern in Practice

Here's the simplified recipe with single-field unions:

1. **Create focused structs** for each action type (no type field needed!)
2. **Use a single T.any()** field in your signature
3. **Let DSPy handle** automatic type detection via the `_type` field
4. **Pattern match** on the result

That's it. No discriminator enums. No manual JSON parsing. No type coercion. No defensive programming. DSPy automatically:
- Adds `_type` field during serialization
- Generates proper JSON schemas with const constraints
- Deserializes to the correct struct type based on `_type`

## Real-World Applications

This coffee shop example might seem silly, but the pattern scales to serious applications:

### Customer Service Agents
```ruby
module ServiceActions
  class CreateTicket < T::Struct
    const :category, String
    const :priority, T.enum([:low, :medium, :high, :urgent])
    const :description, String
  end
  
  class EscalateToHuman < T::Struct
    const :reason, String
    const :department, String
    const :urgency, T.enum([:normal, :immediate])
  end
  
  class ProvideInformation < T::Struct
    const :topic, String
    const :details, String
    const :documentation_links, T::Array[String]
  end
end
```

### DevOps Automation
```ruby
module DevOpsActions
  class ScaleService < T::Struct
    const :service_name, String
    const :replicas, Integer
    const :reason, String
  end
  
  class TriggerAlert < T::Struct
    const :severity, T.enum([:info, :warning, :error, :critical])
    const :message, String
    const :runbook_url, T.nilable(String)
  end
  
  class RunHealthCheck < T::Struct
    const :components, T::Array[String]
    const :deep_check, T::Boolean
  end
end
```

### Code Review Assistant
```ruby
module ReviewActions
  class SuggestRefactor < T::Struct
    const :file_path, String
    const :line_range, T::Array[Integer]
    const :suggestion, String
    const :rationale, String
  end
  
  class FlagSecurityIssue < T::Struct
    const :severity, T.enum([:low, :medium, :high, :critical])
    const :vulnerability_type, String
    const :affected_code, String
    const :remediation, String
  end
  
  class ApproveWithComments < T::Struct
    const :comments, T::Array[String]
    const :follow_up_required, T::Boolean
  end
end
```

## Robustness Against LLM Quirks

One more thing that makes union types in DSPy.rb particularly robust: **automatic field filtering**. 

Sometimes LLMs get creative and return extra fields that aren't part of your struct definition. Maybe the model confuses similar concepts or hallucinates additional properties. With DSPy.rb v0.15.4+, these extra fields are automatically filtered out during type conversion:

```ruby
# Even if the LLM returns this:
{
  "_type" => "RefundOrder",
  "order_id" => "12345",
  "reason" => "Cold coffee",
  "refund_amount" => 4.99,
  "customer_mood" => "angry",  # <- Not in RefundOrder struct!
  "weather" => "rainy"         # <- Also not defined!
}

# DSPy automatically filters to only defined fields:
action = RefundOrder.new(
  order_id: "12345",
  reason: "Cold coffee", 
  refund_amount: 4.99
)
# No errors, no fuss!
```

This means your agents are more resilient to LLM variations and prompt changes. You define what fields you care about, and DSPy ensures that's exactly what you get.

## The Bottom Line

Single-field union types aren't just a nice-to-have - they fundamentally change how you structure AI applications. Instead of defensive programming against a struct full of nils, you get precise types that match your domain.

The coffee shop agent shows how clean this pattern can be:
- **No nil checks**: Each action struct has exactly the fields it needs
- **Type safety**: Pattern matching ensures you handle each action correctly
- **Zero boilerplate**: No discriminator enums or manual type parsing
- **It just works**: DSPy handles all the `_type` field magic automatically

And with DSPy.rb v0.11.0's automatic type detection, the friction is completely gone. You define your structs, use a single `T.any()` field, and DSPy handles all the type magic behind the scenes.

So next time you're building an agent that needs to make decisions, reach for single-field union types. Your future self (and your nil-checking fingers) will thank you.

---

*Want to try it yourself? Check out the [complete coffee shop agent example](https://github.com/vicentereig/dspy.rb/tree/main/examples/coffee-shop-agent) and the [union types documentation](https://vicentereig.github.io/dspy.rb/advanced/complex-types#union-types).*