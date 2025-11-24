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

When teams ask for an "agent," they usually need something far simpler: a predictable chat loop that remembers prior turns, routes complex requests to the right LLM, and leaves room to grow into tools or research flows. DSPy.rb’s type system lets us codify that loop in ~200 lines without ever touching a handwritten prompt.

This post walks through [`examples/ephemeral_memory_chat.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/ephemeral_memory_chat.rb) and shows where to plug in longer-term memory, tool invocation, deep research, and cost controls.

This article shows you how to use dspy.rb conventions to write the simplest agentic flow: a chat with ephemeral memory incorporating the workflow router we introduced in a past post.

## Outline

1. **Typed signatures** – define `ResolveUserQuestion` and the `ComplexityLevel` enum that power both classifiers and responders.
2. **Rails-style lifecycle hooks** – recap from the [Module Runtime Context docs](/core-concepts/module-runtime-context/) how `around` callbacks wrap `forward`, just like `before_action`/`around_action` in Rails controllers, and show why `around :transcribe_chat` is the cleanest place to capture memory.
3. **Simple routing recap** – link back to [Workflow Routing with DSPy.rb](../workflow-routing-with-dspy.rb/) to remind readers how we built a basic classifier-driven router, then extend it here with typed decisions and CLI tooling.
4. **Ephemeral memory in the hook** – walk through the short-term memory struct, how we append user/assistant turns inside the callback, and where to swap in ActiveRecord persistence later.
5. **Production wiring** – show the CLI entrypoint, LM configuration, CLI::UI-based transcript panes, and observability start/flush calls that make the demo runnable.
6. **Extension points** – cover persistence, tool usage, deep research swaps, and memory compaction where hooks already exist.
7. **Next steps** – encourage readers to persist memory, add tools, or compose research loops on top of the same skeleton.

## 1. Typed signatures keep prompts invisible

Everything starts with a signature (here, `ResolveUserQuestion`). Inputs include the user's message, prior turns, and the model we routed to; outputs include the structured reply, inferred complexity, and the next action hint. DSPy.rb compiles the prompt automatically, so the blog example only declares types:

```ruby
class ResolveUserQuestion < DSPy::Signature
  description "Respond while persisting ephemeral memory for routing decisions."

  class MemoryTurn < T::Struct
    const :role, String
    const :message, String
  end

  input do
    const :user_message, String
    const :history, T::Array[MemoryTurn]
    const :selected_model, String
  end

  output do
    const :reply, String
    const :complexity, ComplexityLevel
    const :next_action, String
  end
end
```

Because the signature is typed, any predictor fed with it (a cheap `DSPy::Predict` or a heavier `DSPy::ChainOfThought`) stays in sync with the schema.

## 2. Lifecycle callbacks create ephemeral memory

The agent itself is just a `DSPy::Module`. Instead of overriding `call`, we rely on the built-in callbacks that already wrap `forward`. One `around :manage_turn` hook brackets the work while `forward` stays focused on invoking the routed predictor:

```ruby
class EphemeralMemoryChat < DSPy::Module
  around :manage_turn

  def forward(user_message:)
    route = T.must(@active_route)
    typed_history = @memory[0...-1].map do |turn|
      @memory_turn_struct.new(role: turn.role, message: turn.message)
    end

    route.predictor.call(
      user_message: user_message,
      history: typed_history,
      selected_model: route.model_id
    )
  end

  private

  def manage_turn(_args, kwargs)
    message = kwargs[:user_message] or raise ArgumentError, 'user_message is required'
    @memory << ConversationMemoryEntry.new(role: 'user', message: message, model_id: nil, timestamp: Time.now.utc.iso8601)

    @active_route = @router.call(message: message, memory: @memory)
    result = yield

    if result
      @memory << ConversationMemoryEntry.new(
        role: 'assistant',
        message: result.reply,
        model_id: @active_route.model_id,
        timestamp: Time.now.utc.iso8601
      )
      @last_route = @active_route
    end

    result
  ensure
    @active_route = nil
  end
end
```

This is the simplest possible “agent loop”: before each turn we append the user message, choose the right predictor, run it, then append the assistant response. Because callbacks already target `forward`, we keep DSPy’s observability instrumentation intact while still wrapping custom memory logic.

## 3. Cost-aware routing stays tiny

Routing is just another module:

```ruby
class ChatRouter < DSPy::Module
  def initialize(classifier:, routes:, default_level: ComplexityLevel::Routine)
    super()
    @classifier = classifier
    @routes     = routes
    @default    = default_level
  end

  def call(message:, memory: [])
    classification = @classifier.call(
      message: message,
      conversation_depth: memory.length
    )

    predictor = @routes.fetch(classification.level, @routes[@default])

    RouteDecision.new(
      predictor: predictor,
      model_id: predictor.lm&.model_id || DSPy.config.lm&.model_id || 'unknown',
      level: classification.level,
      reason: classification.reason,
      cost_tier: classification.suggested_cost_tier
    )
  end
end
```

In the demo CLI, lightweight prompts (`gpt-4o-mini`) handle routine turns while a heavier model handles “critical” requests. If you want to add a deep-research flow tomorrow, just register another predictor in the `routes` hash and teach the classifier a new level.

## 4. Where to persist real memory

The blog sample only keeps ephemeral in-memory structs so the reader can see the lifecycle hooks clearly. To persist memory across processes, swap in `DSPy::Memory::MemoryManager` inside `manage_turn`:

```ruby
store = DSPy::Memory.manager
store.store_memory(message, user_id: session_id, tags: ['chat'])
```

That same hook is where you’d compact memory (via `MemoryCompactor`) or attach embeddings to support semantic recall.

## 5. Where tools or Deep Research would slot in

Once the foundation works, three straightforward extensions are highlighted in comments inside the example:

1. **Add tools** – create a `DSPy::Tools::Toolset` (for example, a LangChain-style calculator or calendar) and pass those tools to a `DSPy::ReAct` predictor inside the router map. Because each branch is typed, the tool-using predictor still returns the same struct and can coexist with plain text predictors.
2. **Start a Deep Research flow** – replace the heavy predictor with `DSPy::DeepResearchWithMemory` to auto-loop research steps. The `selected_model` field is already wired, so swapping the predictor doesn’t break the CLI.
3. **Compact memory** – invoke `DSPy::Memory::MemoryCompactor` inside `manage_turn` after the assistant response to keep the transcript lean.

## 6. Observability stays one line

Right after configuring the LM, the script calls `DSPy::Observability.configure!` and flushes spans before exiting. That’s enough to capture every routed turn in Langfuse, Honeycomb, or whichever exporter you wired via `DSPY_WITH_LANGFUSE`.

## 7. What’s next?

Because everything hinges on lifecycle callbacks and typed signatures, scaling up is incremental:

- Swap the router’s classifier to a different model or add more `ComplexityLevel` entries without touching the loop.
- Extend `ConversationMemoryEntry` with `tool_calls` or `attachments` if you decide to add structured tool logs.
- Promote the chat to a managed agent by replacing the predictors with `DSPy::ReAct` or `DSPy::CodeAct`—the surrounding module and memory system stay intact.

## Reader Next Steps

1. Add a `ReAct` or `CodeAct` step inside the router for certain complexity levels so the session can call tools.
2. Layer in light context engineering: before calling the predictor, select the most relevant memory snippets using the `informers` gem plus an embedding model, then pass that trimmed context into the signature.
3. Persist the short-term memory to ActiveRecord (or another store) so the CLI can resume conversations, then experiment with compaction/recall strategies once the transcript grows.

Grab the runnable script with:

```bash
OPENAI_API_KEY=sk-your-key-here \
  bundle exec ruby examples/ephemeral_memory_chat.rb
```

This is a strong, simple foundation—typed inputs/outputs, minimal Ruby hooks, and a clear place to persist state—before you jump into multi-agent orchestration. In DSPy.rb, agent ergonomics come from ordinary Ruby composition, not from a separate runtime.
