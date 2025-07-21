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

<!-- TODO: Update description to remove reference to old :type field pattern per ADR-004 (issue #45) -->

Ever built an AI agent that needs to decide between different actions? You know the drill - create a struct with a dozen nilable fields, then play whack-a-mole with nil checks. There's a better way, and DSPy.rb now makes it automatic with single-field union types.

## The Problem: Decision Paralysis in Code Form

Picture this: You're building a research assistant that can spawn tasks, mark them complete, or ask for clarification. The naive approach looks like:

```ruby
# 😱 The horror of nilable everything@unioz
class AgentAction < T::Struct
  const :spawn_task_description, T.nilable(String)
  const :spawn_task_priority, T.nilable(String)
  const :complete_task_id, T.nilable(String)
  const :complete_task_reason, T.nilable(String)
  const :clarification_question, T.nilable(String)
  # ... 10 more nilable fields
end
```

This is what I call "struct sprawl" - one struct trying to be everything to everyone. It's the code equivalent of a Swiss Army knife where all the tools fall out when you open it.

## Enter Single-Field Union Types: One Decision, Multiple Paths

Here's the thing about AI agents - they make *one* decision at a time. So why not model it that way?

```ruby
# Each action type gets its own focused struct - no type field needed!
module AgentActions
  class SpawnTask < T::Struct
    const :description, String
    const :priority, T.enum([:low, :medium, :high])
  end
  
  class CompleteTask < T::Struct
    const :task_id, String
    const :summary, String
  end
  
  class AskClarification < T::Struct
    const :question, String
    const :context, T.nilable(String)
  end
end
```

See the difference? Each struct has *only* the fields it needs. No more nil checks. No more "wait, which fields go with which action?" And with DSPy.rb's automatic type detection, you don't even need to define a type field - DSPy handles that for you!

## The Magic: Automatic Type Detection

Here's where DSPy.rb's new single-field union types shine. You just use a single `T.any()` field, and DSPy handles everything:

```ruby
class AgentDecisionSignature < DSPy::Signature
  description "Agent decision making"
  
  output do
    const :action, T.any(      # Just one field!
      AgentActions::SpawnTask,
      AgentActions::CompleteTask,
      AgentActions::AskClarification
    )
    const :reasoning, String
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
    "_type": "SpawnTask",
    "description": "Research climate change impacts",
    "priority": "high"
  },
  "reasoning": "User requested information about climate change"
}
```

DSPy automatically converts it to a `SpawnTask` instance. No manual parsing. No discriminator enums. No type checking. It just works!

## A Silly Agent Demo: The Coffee Shop Manager

Let's build something fun - an AI coffee shop manager that handles customer requests. It demonstrates the pattern without getting bogged down in complexity.

```ruby
require 'dspy'

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
    @decision_maker.configure do |config|
      config.lm = DSPy::LM.new('anthropic/claude-3-5-sonnet-20241022')
    end
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
      puts "Customizations: #{result.action.customizations.join(', ')}"
    when CoffeeShopActions::RefundOrder
      puts "Processing refund of $#{result.action.refund_amount}"
      puts "Reason: #{result.action.reason}"
    when CoffeeShopActions::CallManager
      puts "📞 Calling manager about: #{result.action.issue}"
      puts "Urgency: #{result.action.urgency}"
    when CoffeeShopActions::Joke
      puts "😄 #{result.action.setup}"
      puts "😂 #{result.action.punchline}"
    end
    
    puts "\n💬 Response to customer: #{result.friendly_response}"
  end
end

# Let's see it in action!
agent = CoffeeShopAgent.new

# Happy customer
agent.handle_customer(
  request: "Can I get a large iced latte with oat milk?",
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

This pattern shines in:
- **Multi-step agents**: Each step can return different action types
- **Tool-calling systems**: Each tool gets its own parameter struct
- **Workflow engines**: Different node types with specific configurations
- **Chat interfaces**: Handle commands, queries, and actions differently

## The Bottom Line

Single-field union types aren't just a nice-to-have - they fundamentally change how you structure AI applications. Instead of defensive programming against a struct full of nils, you get precise types that match your domain.

And with DSPy.rb's automatic type detection, the friction is completely gone. You define your structs, use a single `T.any()` field, and DSPy handles all the type magic behind the scenes. Your LLM returns JSON with the `_type` field, you get typed Ruby objects. No boilerplate. No configuration. It just works.

So next time you're building an agent that needs to make decisions, reach for single-field union types. Your future self (and your nil-checking fingers) will thank you.

---

*Want to try it yourself? Check out the [complete example](https://github.com/vicentereig/dspy.rb/tree/main/examples/coffee-shop-agent) and the [union types documentation](/advanced/complex-types/#union-types).*