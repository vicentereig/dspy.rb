---
layout: blog
title: "Ephemeral Memory Chat with Router"
description: "Build the simplest DSPy.rb agent loop with typed signatures, lifecycle callbacks, and cost-aware routing before layering tools, memory compaction, or deep-research workflows."
date: 2025-11-23
author: "Vicente Reig"
category: "Agents"
reading_time: "5 min read"
image: /images/og/ephemeral-memory-chat.png
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/ephemeral-memory-chat-router/"
---

When teams ask for an "AI Agent" they usually need something far simpler: a predictable chat loop that remembers prior turns. 
It maybe routes complex requests to the right LLM, and leaves room to grow into tools or research flows. 
[DSPy.rb’s](/core-concepts/signatures/) Signatures and Modules let us codify that loop in ~200 lines without ever 
touching a handwritten prompt.

This article shows you how to use dspy.rb conventions to write the simplest _agentic_ flow: a chat with ephemeral memory incorporating the workflow router we introduced in a past post. 

We will walk through [`examples/ephemeral_memory_chat.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/ephemeral_memory_chat.rb) and shows where to plug in longer-term memory, tool invocation, deep research, and cost controls.

## Outline

1. **Typed signatures** – define `ResolveUserQuestion` and the `ComplexityLevel` enum that power both classifiers and responders.
2. **Rails-style lifecycle hooks** – recap from the [Module Runtime Context docs](/core-concepts/module-runtime-context/) how `around` callbacks wrap `forward`, just like `before_action`/`around_action` in Rails controllers, and show why `around :update_memory` is the cleanest place to capture memory.
3. **Simple routing recap** – link back to [Workflow Routing with DSPy.rb](../workflow-routing-with-dspy.rb/) to remind readers how we built a basic classifier-driven router, then extend it here with typed decisions and CLI tooling.
4. **Ephemeral memory in the hook** – walk through the short-term memory struct, how we append user/assistant turns inside the callback.
5. **Extension points** – long-term memory persistence, tool usage or semantically select memories.

## Writing Typed Signatures to keep Prompts Tidy

Everything starts with a signature `ResolveUserQuestion`. In a world where models and prompting techniques change and improve constantly, Signatures are the anchor your app needs in a world where everything changes constantrly.
A Signature is a contract. A function that wraps the prompt that answer a user's query. DSPy.rb compiles the signature automatically, so the blog example only declares Sorbet Runtime types:

```ruby
class ResolveUserQuestion < DSPy::Signature
  description "Respond while persisting ephemeral memory for routing decisions."
  
  class MemoryTurn < T::Struct
    const :role, String
    const :message, String
  end

  input do
    const :user_message, String
    const :history, T::Array[MemoryTurn], default: []
  end

  output do
    const :reply, String
    const :complexity, ComplexityLevel
  end
end
```
This is how you model a conversation with memory the functional way. So you can focus on modeling the domain objects and relationships
the same way you do in your Rails apps. You don't have to change the way you think to build with LLMs.

Because the signature is typed and coupled from the prompting technique, you can feed it ot 
a cheap `DSPy::Predict` or a heavier `DSPy::ChainOfThought`. 

Okay, wait a minute. How do I send my prompt to my fave LLM again?

```ruby
resolve_question = DSPy::Predict.new(ResolveUserQuestion)
resolved_question = resolve_question.call(user_message: 'Tell me everything you know about me')
puts resolved_question.reply
```

Signatures are decoupled from the Prompting Techniques.You know about the cheap predictor `DSPy::Predict` and its heavier cousing `DSPy::ChainOfThought` that DSPy ships in the core. Alongside the classic tool-wielding technique: `DSPy::ReAct`. 
With them we are modeling the conversation as a sequence of `MemoryTurn`. In this naive example we are feeding the whole converstion back to the LLM. However,
we could easily the informer gem to semantically select the closests memories to each user message if we wanted to manage the context we are passing each time.

We keep a separate `ConversationMemoryEntry` struct for UI and persistence enriching it with additional attributes that would add unnecersary noise to the prompt. 

You haven't written a single prompt manually here, you are just using Ruby objects to handle the size and the shape of the underlying compiled baseline prompt.

That tiny seam creates a natural “context budget” checkpoint: you can trim or redact anything you don’t 
want the model to see while still retaining a richer transcript for analytics or storage. 
It’s the same separation of concerns you use in Rails—domain object vs. serializer—just applied to prompts.

## Lifecycle callbacks create ephemeral memory

The agent itself is just a `DSPy::Module`. Agents are just slightly more sophisticated Prompting Techniques. 
Instead of overriding `call`, we rely on the built-in callbacks that already wrap `forward`.  Pretty much like a Rails Controller, one `around :manage_turn` hook brackets the work while `forward` stays focused on invoking the routed predictor:

```ruby
class EphemeralMemoryChat < DSPy::Module
  attr_accessor :active_route
  around :update_memory

  def forward(user_message:)
    active_route = @router.call(message: message, memory: @memory)
    memory_turns = @memory[0...-1].map do |turn|
      MemoryTurn.new(role: turn.role, message: turn.message)
    end

    resolved_question = active_route.predictor.call(
      user_message: user_message,
      history: memory_turns,
      selected_model: route.model_id
    )

    resolved_question
  end

  private
  # receives the same args as forward 
  def update_memory(_args, kwargs)
    message = kwargs[:user_message] or raise ArgumentError, 'user_message is required'
    @memory << ConversationMemoryEntry.new(role: 'user', message: message, model_id: nil, timestamp: Time.now.utc.iso8601)
   
    result = yield

    if result
      @memory << ConversationMemoryEntry.new(
        role: 'assistant',
        message: result.reply,
        model_id: active_route.model_id,
        timestamp: Time.now.utc.iso8601
      )
    end
  end
end
```

Despite the workflow router, this is the simplest possible “agent loop”: before each turn we append the user message, 
choose the right predictor, run it, then append the assistant response. Because callbacks already target `forward`, 
we keep DSPy’s observability instrumentation intact while still wrapping custom memory logic.
