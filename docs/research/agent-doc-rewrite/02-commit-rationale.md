# Commit Rationale

Date: 2026-04-04

This file captures the adjacent-project commit history that most clearly explains the tutorial direction.

## observo-server

### `5af5341` Split monolithic GazetteNavigator into phase-scoped DSPy modules

What changed:

- one large selector became phase-scoped modules
- action space got smaller per phase
- invalid actions became impossible at the schema level

Why it matters:

- architecture beat prompt wording
- phase constraints moved from "please behave" to actual type/schema boundaries
- this is the clearest argument for teaching agents as software structure

Lesson for the docs:

- show how reducing the action surface produces better agents
- teach phase separation as a first-class pattern, not an advanced trick

### `1babbb6` Add tool-calling mode to GazetteNavigator

What changed:

- tool schemas were presented directly to the LLM
- dispatch moved through `dynamic_call`
- the system became closer to MCP/ReAct patterns

Why it matters:

- typed tools scale better than ever-larger selection signatures
- tool calling simplifies the runtime loop
- capability design becomes Ruby code instead of prompt sprawl

Lesson for the docs:

- introduce tools early
- make tool contracts a core part of the tutorial spine

### `36dc7fb` Never expose document content inline, enforce RLM-only access

What changed:

- content stopped flowing through multiple paths
- document text became accessible only through the explicit navigation mechanism

Why it matters:

- a good agent architecture protects context boundaries
- one source of truth is easier to reason about and audit
- "more context" is not automatically "better architecture"

Lesson for the docs:

- teach deliberate context flow
- include at least one section on visibility boundaries and evidence access

## junipero

### `fab143e` Implement agent-native two-phase answer synthesis for RLM

What changed:

- navigation stopped producing final answers directly
- synthesis became its own signature
- internal fields were marked as internal

Why it matters:

- this is the cleanest statement of the navigation/synthesis split
- user-visible output became a separate concern from exploration
- the architecture fixed a concrete bug, not just style

Lesson for the docs:

- one of the central sections should show the diff from single-loop agent to two-phase agent
- stress that this improves correctness, not just elegance

### `09cb9c0` Add typed ChatMessage struct for conversation history

What changed:

- conversation history moved from loose hashes to `ChatMessage`

Why it matters:

- even agent memory should be typed
- once history has a real shape, workflows and tests simplify

Lesson for the docs:

- include a section where state/history becomes a `T::Struct`
- explain that type safety is not just for the final answer object

### `5a2438c` Dynamic tool call summary updates via Turbo Stream

What changed:

- tool activity became visible in real time
- the UI summary stayed in sync with workflow step updates

Why it matters:

- observability is part of the product experience
- users trust agents more when the loop is inspectable

Lesson for the docs:

- production guidance should include operator and user visibility
- the single page should argue for step-level traces as a product feature

## Synthesis

The commit history points to one consistent direction:

- fewer giant prompts
- more typed contracts
- smaller action surfaces
- cleaner context boundaries
- observable loops
- explicit separation between internal work and external answers

That should be the document's backbone.
