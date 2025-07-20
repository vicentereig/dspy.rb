---
layout: blog
name: "Union Types: The Secret to Cleaner AI Agent Workflows"
date: 2025-01-20
categories: [patterns, agents]
description: How DSPy.rb's automatic type conversion makes building AI agents surprisingly simple
toc: true
permalink: /blog/union-types-agentic-workflows/
image:
  path: /assets/images/blog/union-types-agent.jpg
  alt: AI agent workflow with union types
---

Ever built an AI agent that needs to decide between different actions? You know the drill - create a struct with a dozen nilable fields, then play whack-a-mole with nil checks. There's a better way, and DSPy.rb now makes it automatic.

## The Problem: Decision Paralysis in Code Form

Picture this: You're building a research assistant that can spawn tasks, mark them complete, or ask for clarification. The naive approach looks like:

```ruby
# 😱 The horror of nilable everything
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

## Enter Union Types: One Decision, Multiple Paths

Here's the thing about AI agents - they make *one* decision at a time. So why not model it that way?

```ruby
# Each action type gets its own focused struct
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

See the difference? Each struct has *only* the fields it needs. No more nil checks. No more "wait, which fields go with which action?"

## The Magic: Automatic Type Conversion

Here's where DSPy.rb shines. When you use union types in a signature, DSPy automatically converts the LLM's JSON response to the right struct type:

```ruby
class AgentDecisionSignature < DSPy::Signature
  # Define what actions are possible
  class ActionType < T::Enum
    enums do
      SpawnTask = new('spawn_task')
      CompleteTask = new('complete_task')
      AskClarification = new('ask_clarification')
    end
  end
  
  output do
    const :action, ActionType  # The discriminator
    const :details, T.any(     # The union type
      AgentActions::SpawnTask,
      AgentActions::CompleteTask,
      AgentActions::AskClarification
    )
    const :reasoning, String
  end
end
```

When the LLM returns `{"action": "spawn_task", "details": {...}}`, DSPy:
1. Converts `"spawn_task"` to `ActionType::SpawnTask`
2. Looks at the union type and figures out which struct to use
3. Converts the details hash to a `SpawnTask` instance

No manual parsing. No type checking. It just works.

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

# The orchestrator (using Claude Opus 4) decides what to do
class OrchestratorSignature < DSPy::Signature
  description "Analyze customer request and decide on action"
  
  class ActionType < T::Enum
    enums do
      MakeDrink = new('make_drink')
      RefundOrder = new('refund_order')
      CallManager = new('call_manager')
      TellJoke = new('tell_joke')
    end
  end
  
  input do
    const :customer_request, String
    const :customer_mood, T.enum([:happy, :neutral, :upset])
    const :time_of_day, String
  end
  
  output do
    const :action_type, ActionType
    const :priority, T.enum([:low, :medium, :high])
    const :reasoning, String
  end
end

# The executor (using Claude Sonnet 4) carries out the action
class ExecutorSignature < DSPy::Signature
  description "Execute the decided action with specific details"
  
  input do
    const :action_type, String
    const :customer_request, String
    const :additional_context, String
  end
  
  output do
    const :action, OrchestratorSignature::ActionType  # Use the same enum
    const :details, T.any(
      CoffeeShopActions::MakeDrink,
      CoffeeShopActions::RefundOrder,
      CoffeeShopActions::CallManager,
      CoffeeShopActions::Joke
    )
    const :friendly_response, String
  end
end

# The actual agent
class CoffeeShopAgent < DSPy::Module
  def initialize
    super()
    # Opus for high-level reasoning
    @orchestrator = DSPy::ChainOfThought.new(
      OrchestratorSignature,
      lm: DSPy::LM::Anthropic.new(model: "claude-3-opus-20240229")
    )
    
    # Sonnet for execution details
    @executor = DSPy::Predict.new(
      ExecutorSignature,
      lm: DSPy::LM::Anthropic.new(model: "claude-3-5-sonnet-20241022")
    )
  end
  
  def handle_customer(request:, mood: :neutral, time: "afternoon")
    # Step 1: Orchestrator decides strategy
    decision = @orchestrator.call(
      customer_request: request,
      customer_mood: mood,
      time_of_day: time
    )
    
    puts "🧠 Orchestrator reasoning: #{decision.reasoning}"
    puts "📋 Decided action: #{decision.action_type.serialize}"
    
    # Step 2: Executor handles the details
    result = @executor.call(
      action_type: decision.action_type.serialize,
      customer_request: request,
      additional_context: decision.reasoning
    )
    
    # Step 3: Pattern match on the result
    puts "\n☕ Taking action..."
    case result.details
    when CoffeeShopActions::MakeDrink
      puts "Making a #{result.details.size} #{result.details.drink_type}"
      puts "Customizations: #{result.details.customizations.join(', ')}"
    when CoffeeShopActions::RefundOrder
      puts "Processing refund of $#{result.details.refund_amount}"
      puts "Reason: #{result.details.reason}"
    when CoffeeShopActions::CallManager
      puts "📞 Calling manager about: #{result.details.issue}"
      puts "Urgency: #{result.details.urgency}"
    when CoffeeShopActions::Joke
      puts "😄 #{result.details.setup}"
      puts "😂 #{result.details.punchline}"
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

Here's the recipe:

1. **Define an enum** for your action types
2. **Create focused structs** for each action's data
3. **Use T.any()** to create the union type
4. **Let DSPy handle** the type conversion
5. **Pattern match** on the result

That's it. No manual JSON parsing. No type coercion. No defensive programming.

## Real-World Applications

This pattern shines in:
- **Multi-step agents**: Each step can return different action types
- **Tool-calling systems**: Each tool gets its own parameter struct
- **Workflow engines**: Different node types with specific configurations
- **Chat interfaces**: Handle commands, queries, and actions differently

## The Bottom Line

Union types aren't just a nice-to-have - they fundamentally change how you structure AI applications. Instead of defensive programming against a struct full of nils, you get precise types that match your domain.

And with DSPy.rb's automatic conversion, the friction is gone. Your LLM returns JSON, you get typed Ruby objects. It's that simple.

So next time you're building an agent that needs to make decisions, reach for union types. Your future self (and your nil-checking fingers) will thank you.

---

*Want to try it yourself? Check out the [complete example](https://github.com/vicentereig/dspy.rb/tree/main/examples/coffee-shop-agent) and the [union types documentation](/advanced/complex-types/#union-types).*