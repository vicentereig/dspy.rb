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

### What?

Start with a `DSPy::Signature` that defines the agent boundary with real Ruby types: inputs, outputs, enums, and structs.

### So What?

This is the first moment where DSPy.rb stops being "prompt engineering in Ruby" and becomes software design:

- callers know what the agent expects
- the model is constrained by a schema
- outputs become objects the rest of the app can trust
- tests can assert on behavior instead of string fragments

### What Not?

- Do not begin with a giant prompt string.
- Do not return free-form JSON blobs when the output shape is knowable.
- Do not hide critical branching decisions inside prose when they can be enums or unions.

## Pattern 2: Tools Beat Prompt Mazes

### What?

Expose capabilities as typed tools or toolsets instead of embedding every possible action in a monolithic prompt.

### So What?

Tool schemas make the agent legible:

- the available actions are explicit
- arguments are validated at the boundary
- capability changes happen in Ruby, not in fragile prompt text
- the agent loop can stay small because execution lives in tools

### What Not?

- Do not model a multi-capability agent as one signature with dozens of nullable fields.
- Do not make the model "pretend" to use tools by describing side effects in text.
- Do not pass around untyped hashes when a `T::Struct` or tool schema can do the job.

## Pattern 3: Navigation And Synthesis Are Different Jobs

### What?

Use one primitive to explore and collect evidence, then another to turn that evidence into the user-visible answer.

### So What?

This prevents one of the most common agent failures: the model answers too early because it confuses internal context with the final response.

The strongest real-world pattern here is:

- inner loop: gather, compare, search, fetch, narrow
- final step: synthesize only after the loop explicitly requests finish

### What Not?

- Do not ask the same predictor to both decide the next step and write the final answer.
- Do not let the model treat raw context windows as user-facing output.
- Do not rely on "be careful" prompt language when phase separation can be encoded in architecture.

## Pattern 4: State Is A Type

### What?

Represent budget, iteration count, fetched documents, active context, and phase transitions with typed structs.

### So What?

Explicit state makes the agent resumable, inspectable, and composable:

- easier to checkpoint
- easier to debug
- easier to pass between modules
- easier to test without the model in the loop

### What Not?

- Do not let state leak into instance variables with no formal shape.
- Do not store important loop control data only in natural language history.
- Do not overload the prompt with state the runtime should own directly.

## Pattern 5: Async Is Part Of The Architecture

### What?

When the agent needs to fan out across independent I/O, use Ruby async primitives as part of the design, not as an afterthought.

### So What?

This is one of the clearest "modern Ruby" advantages:

- multiple fetches can overlap
- retries stop blocking unrelated work
- agents stay responsive under imperfect networks
- async becomes a tool for agent quality, not just performance

### What Not?

- Do not serialize obviously parallel fetches.
- Do not bury concurrency inside opaque infrastructure if the tutorial is teaching how agents actually work.
- Do not promise async benefits without showing the architectural seam where concurrency enters.

## Pattern 6: Step-Level Observability Is Non-Negotiable

### What?

Emit step events for selection, tool calls, checkpoints, and synthesis.

### So What?

The tutorial should show that a production agent needs an audit trail:

- what it tried
- why it tried it
- which tool ran
- what came back
- why it stopped

This is the difference between a demo and a system you can operate.

### What Not?

- Do not reduce observability to token counts and latency charts.
- Do not present traces as optional polish.
- Do not hide intermediate reasoning and tool execution if the page is arguing for auditable agents.

## Pattern 7: Bounded Loops, Not Magical Autonomy

### What?

Use explicit budgets: iterations, recursion depth, fetch limits, or timeouts.

### So What?

Real agents need autonomy with rails:

- they stop
- they degrade predictably
- they surface incomplete work
- they remain affordable

### What Not?

- Do not present "autonomous" as "unbounded."
- Do not depend on the model to self-regulate forever.
- Do not leave the reader without a concrete list of budgets to set.

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

Every major section should use:

- `What?`
- `So What?`
- `What Not?`

That pattern matches the intended audience:

- humans get an opinionated explanation
- agents get a predictable parsing structure
