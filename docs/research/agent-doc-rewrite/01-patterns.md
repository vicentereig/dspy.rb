# Agent Tutorial Patterns

Date: 2026-04-04

## Goal

Replace the current docs-portal shape with a single long-form tutorial that teaches one agent properly.

The page should feel like an essay, not a reference site. It should still work for agents by keeping section boundaries explicit, examples typed, and architecture decisions easy to extract.

## Candidate Tutorial System

**Working title:** Evidence Brief Agent

The agent answers a research question against a corpus, gathers evidence with tools, keeps state explicitly, and only then produces a user-facing answer.

Why this system:

- It is an actual agent, not a pipeline.
- It shows typed inputs, typed tools, typed state, and typed output.
- It creates a natural reason to separate exploration from synthesis.
- It benefits from async document fetches and observable step events.
- It matches the strongest patterns already emerging in real DSPy.rb work.

## Pattern 1: Typed Contracts First

### Definition

Start with a `DSPy::Signature` that defines the agent boundary with real Ruby types: inputs, outputs, enums, and structs.

### Why It Matters

This is the first moment where DSPy.rb stops being "prompt engineering in Ruby" and becomes software design:

- callers know what the agent expects
- the model is constrained by a schema
- outputs become objects the rest of the app can trust
- tests can assert on behavior instead of string fragments

### Next Move

- Type the output of one existing agent before you touch optimization.
- Replace one free-form string field with a struct or enum where the shape is already known.
- Use the contract to define what "done" means for the agent.

## Pattern 2: Tools Beat Prompt Mazes

### Definition

Expose capabilities as typed tools or toolsets instead of embedding every possible action in a monolithic prompt.

### Why It Matters

Tool schemas make the agent legible:

- the available actions are explicit
- arguments are validated at the boundary
- capability changes happen in Ruby, not in fragile prompt text
- the agent loop can stay small because execution lives in tools

### Next Move

- Extract the first two capabilities your prompt is currently pretending to have.
- Turn those capabilities into typed tools with real return values.
- Let tool schemas narrow the action space instead of prompt text.

## Pattern 3: Navigation And Synthesis Are Different Jobs

### Definition

Use one primitive to explore and collect evidence, then another to turn that evidence into the user-visible answer.

### Why It Matters

This prevents one of the most common agent failures: the model answers too early because it confuses internal context with the final response.

The strongest real-world pattern here is:

- inner loop: gather, compare, search, fetch, narrow
- final step: synthesize only after the loop explicitly requests finish

### Next Move

- Split one multi-step agent into exploration and synthesis responsibilities.
- Remove final-answer generation from the inner loop.
- Make visibility boundaries explicit in signatures and field descriptions.

## Pattern 4: State Is A Type

### Definition

Represent budget, iteration count, fetched documents, active context, and phase transitions with typed structs.

### Why It Matters

Explicit state makes the agent resumable, inspectable, and composable:

- easier to checkpoint
- easier to debug
- easier to pass between modules
- easier to test without the model in the loop

### Next Move

- Create one typed state object for loop control.
- Move fetched ids, evidence, and budgets into that struct.
- Use it as the checkpoint and resume boundary.

## Pattern 5: Async Is Part Of The Architecture

### Definition

When the agent needs to fan out across independent I/O, use Ruby async primitives as part of the design, not as an afterthought.

### Why It Matters

This is one of the clearest "modern Ruby" advantages:

- multiple fetches can overlap
- retries stop blocking unrelated work
- agents stay responsive under imperfect networks
- async becomes a tool for agent quality, not just performance

### Next Move

- Find the first obviously independent fetch batch.
- Add async fan-out there and nowhere else yet.
- Measure responsiveness and throughput after the change.

## Pattern 6: Step-Level Observability Is Non-Negotiable

### Definition

Emit step events for selection, tool calls, checkpoints, and synthesis.

### Why It Matters

The tutorial should show that a production agent needs an audit trail:

- what it tried
- why it tried it
- which tool ran
- what came back
- why it stopped

This is the difference between a demo and a system you can operate.

### Next Move

- Add step events for selection, tool calls, and synthesis.
- Preserve enough detail to explain what the agent did after the fact.
- Treat traces as part of the product, not an optional dashboard.

## Pattern 7: Bounded Loops, Not Magical Autonomy

### Definition

Use explicit budgets: iterations, recursion depth, fetch limits, or timeouts.

### Why It Matters

Real agents need autonomy with rails:

- they stop
- they degrade predictably
- they surface incomplete work
- they remain affordable

### Next Move

- Set explicit iteration, recursion, or time budgets.
- Decide what the agent returns when it runs out of room.
- Make bounded behavior visible in tests and traces.

## Tutorial Spine

The single page should teach this progression:

1. Start with a typed signature.
2. Wrap it in a small module.
3. Add typed tools.
4. Convert it into an evidence-gathering agent.
5. Split navigation from synthesis.
6. Make state explicit.
7. Add async fan-out.
8. Add observability and tests.

Every major section should answer:

- what it is
- why it matters
- what to do next

That pattern matches the intended audience:

- humans get an opinionated explanation
- agents get a predictable parsing structure
