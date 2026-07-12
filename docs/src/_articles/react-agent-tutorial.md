---
layout: blog
title: "Building Your First ReAct Agent in Ruby"
description: "Build a bounded ReAct agent whose model chooses among typed Ruby tools while DSPy.rb records each action and observation."
date: 2025-06-28
author: "Vicente Reig"
category: "Tutorial"
reading_time: "12 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/react-agent-tutorial/"
image: /images/og/react-agent-tutorial.png
---

A workflow follows branches written in Ruby. A ReAct agent gives the model a smaller, bounded decision: choose the next tool, inspect its result, and either continue or finish.

This tutorial builds a research assistant with typed tools and a five-iteration limit. DSPy.rb constructs the provider prompts from the signature, tool schemas, and accumulated history. You define the task and the operations the model may select.

## The ReAct loop

`DSPy::ReAct` repeats four steps:

1. Generate a thought and select an action.
2. Validate the selected tool and its input.
3. Call the Ruby tool and record its observation.
4. Ask the model whether to use another tool or finish.

The model chooses actions inside that loop. The application still owns the available tools, input types, maximum iterations, and side effects. Those boundaries are the agent's harness.

## Define typed tools

Tools inherit from `DSPy::Tools::Base`. The Sorbet signature on `call` becomes the tool's input schema:

```ruby
class WebSearchTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'web_search'
  tool_description 'Searches the web for information on a given topic'

  class SearchResult < T::Struct
    const :title, String
    const :url, String
    const :snippet, String
  end

  sig { params(query: String).returns(T::Array[SearchResult]) }
  def call(query:)
    case query.downcase
    when /ruby programming/
      [
        SearchResult.new(
          title: "Ruby Programming Language",
          url: "https://ruby-lang.org",
          snippet: "A dynamic, open source programming language..."
        )
      ]
    when /climate change/
      [
        SearchResult.new(
          title: "NASA Climate Data",
          url: "https://climate.nasa.gov",
          snippet: "Climate data and research..."
        )
      ]
    else
      []
    end
  end
end

class DataAnalysisTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'data_analysis'
  tool_description 'Calculates the mean or median of numerical data'

  sig { params(data: T::Array[Float], operation: String).returns(Float) }
  def call(data:, operation:)
    raise ArgumentError, "Data cannot be empty" if data.empty?

    case operation
    when "mean"
      data.sum / data.length
    when "median"
      sorted = data.sort
      middle = sorted.length / 2
      sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    else
      raise ArgumentError, "Unsupported operation: #{operation}"
    end
  end
end
```

The schema constrains tool arguments and lets DSPy.rb coerce them before invocation. It does not make a side effect safe. A database, HTTP, shell, or payment tool still needs its own authorization, timeouts, rate limits, and input policy.

## Define the task

The signature describes the inputs and the final typed result. It does not prescribe the order of tool calls:

```ruby
class ResearchDepth < T::Enum
  enums do
    Basic = new('basic')
    Detailed = new('detailed')
    Comprehensive = new('comprehensive')
  end
end

class ResearchAssistant < DSPy::Signature
  description "Research a topic and summarize findings from the available tools."

  input do
    const :topic, String, description: "The topic to research"
    const :depth, ResearchDepth, description: "Requested research depth"
  end

  output do
    const :summary, String, description: "Summary supported by the tool observations"
    const :key_statistics, T::Array[String], description: "Relevant numbers and facts"
    const :sources, T::Array[String], description: "Source URLs used"
    const :confidence, Float, description: "Confidence from 0.0 to 1.0"
  end
end
```

Descriptions still matter. They provide task and field information that DSPy.rb includes in the generated prompt. The difference from prompt-template programming is that the signature remains the application interface while adapters handle provider formatting.

## Construct and run the agent

```ruby
require 'dspy'

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY']
  )
end

research_agent = DSPy::ReAct.new(
  ResearchAssistant,
  tools: [WebSearchTool.new, DataAnalysisTool.new],
  max_iterations: 5
)

result = research_agent.call(
  topic: "Ruby programming language adoption trends",
  depth: ResearchDepth::Detailed
)

puts result.summary
puts result.key_statistics
puts result.sources
puts result.confidence
```

Five iterations is both the explicit limit above and the current default. If the model fails to finish, `DSPy::ReAct` emits a `react.max_iterations` event and raises `DSPy::ReAct::MaxIterationsError` instead of returning a valid typed answer.

## Inspect what the agent did

The returned result includes `history` and `iterations`. Each history item is a `DSPy::HistoryEntry`:

```ruby
result.history.each do |entry|
  puts "Step: #{entry.step}"
  puts "Thought: #{entry.thought}"
  puts "Action: #{entry.action}"
  puts "Tool input: #{entry.tool_input.inspect}"
  puts "Observation: #{entry.observation.inspect}"
end

puts "Total iterations: #{result.iterations}"
```

This history records the model's reported thought, selected action, typed input, and tool result. It is useful execution evidence, but it is not proof that the model's natural-language thought faithfully explains its internal reasoning.

DSPy.rb also emits spans and events for the module, LM calls, tool executions, invalid actions, and maximum-iteration exits. Configure an OpenTelemetry backend when you need traces outside the process.

## Put tools behind real boundaries

A tool is part of the application's authority surface. Keep its interface narrow:

```ruby
class AccountLookupTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'account_lookup'
  tool_description 'Returns support-safe account status for one account ID'

  class AccountStatus < T::Struct
    const :plan, String
    const :active, T::Boolean
  end

  sig { params(account_id: Integer).returns(AccountStatus) }
  def call(account_id:)
    account = Account.find(account_id)
    AccountStatus.new(plan: account.plan_name, active: account.active?)
  end
end
```

Do not expose arbitrary SQL when the agent only needs an account status. Check authorization inside the tool, apply query limits, and separate read tools from tools that mutate data. `max_iterations` limits loop length; it does not limit the damage from one overpowered tool call.

## Test decisions and boundaries

Unit-test tools as ordinary Ruby objects. For the agent, use recorded provider responses or stubs to cover:

- A valid tool call followed by `finish`.
- Unknown actions and malformed tool input.
- Tool exceptions.
- Maximum-iteration behavior.
- Final output coercion against the original signature.

Evaluate complete trajectories when tool choice matters. A correct final string can hide an unnecessary call, an unsafe argument, or a route that costs too much.

## ReAct or a workflow?

Use ReAct when the next operation depends on an observation and the model has a useful bounded choice among tools. Use a deterministic workflow when every step must run, the branch graph is already known, or audit requirements demand explicit transitions.

A workflow can contain a ReAct handler. The surrounding Ruby code still owns budgets, permissions, persistence, fallback behavior, and evaluation. Giving the model one decision does not require giving it all of them.
