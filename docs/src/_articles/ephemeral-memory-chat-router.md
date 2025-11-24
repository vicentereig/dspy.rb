---
layout: blog
title: "From Prompts to Modules: Designing Resilient Ruby Chat Agents with the DSPy Paradigm"
description: "Build the simplest agent loop with typed signatures, lifecycle callbacks, and cost-aware routing before layering tools, memory compaction, or deep-research workflows."
date: 2025-11-23
author: "Vicente Reig"
category: "Agents"
reading_time: "4 min read"
image: /images/og/ephemeral-memory-chat.png
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/ephemeral-memory-chat-router/"
---

When teams ask for an "AI Agent" they usually need something far simpler: a predictable chat loop that remembers prior turns, sometimes routes complex requests to a pricier LLM, and leaves room to grow into tools or research flows. [DSPy.rb’s](/core-concepts/signatures/) Signatures and Modules let us codify that loop in ~200 lines without touching a handwritten prompt.

In this article we’ll use those conventions to build the simplest _agentic_ flow: a chat session with ephemeral memory plus the [workflow router we introduced previously](../workflow-routing-with-dspy.rb/). We’ll walk through [`examples/ephemeral_memory_chat.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/ephemeral_memory_chat.rb) and point out exactly where to plug in longer-term memory, tool invocation, deep research, and cost controls.

## Outline

1. **Typed signatures** – define `ResolveUserQuestion`, its helper structs, and why typed contracts keep prompts tidy.
2. **Lifecycle hooks drive memory** – show how `around :update_memory` brackets `forward` so routing stays in `forward` while callbacks handle transcript storage.
3. **Where to extend** – highlight the seam for routing, longer-term memory, or tools so readers can continue building on the same skeleton.

## Writing Typed Signatures to keep Prompts Tidy

Everything starts with the `ResolveUserQuestion` signature. Models and prompting techniques change constantly, so signatures act as the anchor: a contract that wraps the prompt answering a user’s query. DSPy.rb compiles the signature automatically, so we only declare Sorbet Runtime types:

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
    const :selected_model, String
  end

  output do
    const :reply, String
    const :complexity, ComplexityLevel
  end
end
```
This is how you model a conversation—functionally, with plain structs—so you can keep thinking in terms of domain objects instead of raw prompts.

Because the signature is typed yet decoupled from the prompting technique, you can feed it to a cheap [`DSPy::Predict`]({{ "/core-concepts/predictors/#dspypredict" | relative_url }}) or a heavier [`DSPy::ChainOfThought`]({{ "/core-concepts/predictors/#dspychainofthought" | relative_url }}) without rewriting anything.

Okay, wait a minute. How do I send my prompt to my favorite LLM again?

```ruby
resolve_question = DSPy::Predict.new(ResolveUserQuestion)
resolved_question = resolve_question.call(user_message: 'Tell me everything you know about me')
puts resolved_question.reply
```

Signatures stay decoupled from prompting techniques. DSPy ships multiple techniques—[`DSPy::Predict`]({{ "/core-concepts/predictors/#dspypredict" | relative_url }}), [`DSPy::ChainOfThought`]({{ "/core-concepts/predictors/#dspychainofthought" | relative_url }}), [`DSPy::ReAct`]({{ "/core-concepts/predictors/#dspyreact" | relative_url }})—and they all share this contract. In the naive example above we feed the whole conversation back to the LLM, but we could use the `informers` gem to pick only the most relevant `MemoryTurn`s before dispatching the request.

Meanwhile we keep a richer `ConversationMemoryEntry` struct for UI or persistence, enriching it with attributes (timestamps, model IDs) that would add unnecessary noise to the prompt. That seam becomes a natural “context budget” checkpoint: trim what you don’t want the model to see while retaining a detailed transcript for analytics or storage. It’s the same separation of concerns you use in Rails—domain object vs. serializer—applied to prompts.

## Lifecycle callbacks create ephemeral memory

The agent itself is just a `DSPy::Module`. We rely on the built-in callbacks that already wrap `forward`. The method `call` is just an alias to it. Just like a Rails controller’s `around_action`, `around :update_memory` brackets work while `forward` focuses on routing and invoking the predictor:

```ruby
class EphemeralMemoryChat < DSPy::Module
  around :update_memory

  def initialize(signature:, router:)
    super()
    @signature = signature
    @router = router
    @memory = []
    @current_route = nil
  end

  def current_route
    @current_route
  end

  def current_route=(route)
    @current_route = route
  end

  def forward(user_message:)
    self.current_route = @router.call(message: user_message, memory: @memory)

    memory_turns = @memory[0...-1].map do |memory_entry|
      @signature::MemoryTurn.new(role: memory_entry.role, message: memory_entry.message)
    end

    current_route.predictor.call(
      user_message: user_message,
      history: memory_turns,
      selected_model: current_route.model_id
    )
  end

  private

  # Receives the same args as forward because DSPy pipes them through callbacks.
  def update_memory(_args, kwargs)
    message = kwargs[:user_message] or raise ArgumentError, 'user_message is required'

    @memory << ConversationMemoryEntry.new(
      role: 'user',
      message: message,
      model_id: nil,
      timestamp: Time.now.utc.iso8601
    )

    resolved_question = yield

    if resolved_question && current_route
      @memory << ConversationMemoryEntry.new(
        role: 'assistant',
        message: resolved_question.reply,
        model_id: current_route.model_id,
        timestamp: Time.now.utc.iso8601
      )
    end
  end
end
```

Even with cost-aware routing in play, this stays the simplest possible agent loop: append the user message, choose the right predictor, run it, then append the assistant response. Because callbacks already target `forward`, DSPy’s observability instrumentation—including the root span every `DSPy::Module` emits—stays intact, so Langfuse or any other configured exporter sees the full call stack automatically.

## Wiring the classifier and predictors

The router itself is still plain Ruby. One classifier estimates complexity, then two predictors share the same signature but swap prompting techniques and models:

```ruby
classifier = DSPy::Predict.new(RouteChatRequest)

fast_predictor = DSPy::Predict.new(ResolveUserQuestion)
fast_predictor.configure do |config|
  config.lm = DSPy::LM.new(
    FAST_RESPONSE_MODEL,
    api_key: ENV['OPENAI_API_KEY'],
    structured_outputs: true
  )
end

deep_predictor = DSPy::ChainOfThought.new(ResolveUserQuestion)
deep_predictor.configure do |config|
  config.lm = DSPy::LM.new(
    DEEP_REASONING_MODEL,
    api_key: ENV['OPENAI_API_KEY'],
    structured_outputs: true
  )
end

router = ChatRouter.new(
  classifier: classifier,
  routes: {
    ComplexityLevel::Routine => fast_predictor,
    ComplexityLevel::Detailed => fast_predictor,
    ComplexityLevel::Critical => deep_predictor
  },
  default_level: ComplexityLevel::Routine
)
```

Because every branch shares the `ResolveUserQuestion` signature, you can drop in more predictors (ReAct, DeepResearch, etc.) without rewriting the chat loop—just update the routes hash.

## Where to extend from here

- **Routing knobs** – swap in the classifier from [Workflow Routing with DSPy.rb](../workflow-routing-with-dspy.rb/) or add more `ComplexityLevel` branches without touching the chat loop.
- **Longer-term memory** – hydrate `@memory` from ActiveRecord rows (or `DSPy::Memory`) inside `initialize`, then persist each `ConversationMemoryEntry` inside `update_memory`.
- **Tooling & research** – replace a route’s predictor with [`DSPy::ReAct`](../react-agent-with-dspy.rb/) for tool use, or upgrade the “deep” branch to `DSPy::DeepResearchWithMemory` (see [`examples/deep_research_cli/chat.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/deep_research_cli/chat.rb) for a full walkthrough); the signature contract already matches.
- **Context selection** – before calling the predictor, run [`informers`](https://rubygems.org/gems/informers) or your favorite embedding service to trim the `memory_turns` to only the most relevant entries.

## Key takeaways

- Anchor your app with Signatures so each prompt stays typed, swappable, and testable even as models change.
- Model context with plain Ruby structs (`ConversationMemoryEntry`, `MemoryTurn`) so you can control what reaches the model versus what you persist.
- Use lifecycle callbacks to keep memory concerns lightweight—`around :update_memory` gives you a single seam for recording transcripts or persisting them later.
- Keep routing decisions and predictor wiring together so you always know which LM answered a turn and why it was chosen.

Run the CLI yourself!

```bash
OPENAI_API_KEY=sk-your-key \
bundle exec ruby examples/ephemeral_memory_chat.rb
```
