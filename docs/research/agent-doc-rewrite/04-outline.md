# Single-Page Outline

Date: 2026-04-04

## Proposed Title

`Build One Agent Properly`

Subtitle:

`A single-page DSPy.rb tutorial for building type-safe, async, observable agents in modern Ruby.`

## Core Promise

This page teaches one agent from zero to production shape.

Not workflows. Not abstract concepts. One agent, built incrementally, with diffs, reasons, and mistakes to avoid.

## Tutorial Agent

**Evidence Brief Agent**

The agent answers a question against a corpus of documents:

- searches candidate documents
- fetches relevant evidence
- keeps typed state
- synthesizes a final answer with citations
- exposes its steps for debugging and UI visibility

## Table Of Contents

1. Why This Page Exists
2. The Agent We Are Building
3. Step 1: A Contract Before A Prompt
4. Step 2: Give The Agent Real Tools
5. Step 3: Put The Loop In A Module
6. Step 4: Separate Finding From Answering
7. Step 5: Make State Explicit
8. Step 6: Add Async Fan-Out
9. Step 7: Make The Loop Observable
10. What To Ship
11. What To Read Next

## Section Notes

### 1. Why This Page Exists

Purpose:

- frame DSPy.rb as software architecture for agents
- reuse the "MVC moment" argument
- explain why the docs site is now one page

Subsections:

- explain what it is
- explain why it matters
- end with what to do next

### 2. The Agent We Are Building

Purpose:

- define the example agent clearly
- show the final shape before diving into steps

Artifacts:

- short architecture diagram
- tiny typed output example
- "why this example" note

### 3. Step 1: A Contract Before A Prompt

Purpose:

- start with `DSPy::Signature`
- show a typed `Question`, `Citation`, and `Answer`

Artifacts:

- initial code snippet
- diff from loose string output to typed output

### 4. Step 2: Give The Agent Real Tools

Purpose:

- introduce `search_corpus` and `fetch_document`
- show tool returns as typed structs

Artifacts:

- tool definitions
- diff replacing prompt instructions with actual tools

### 5. Step 3: Put The Loop In A Module

Purpose:

- move from isolated predictor calls to a `DSPy::Module`
- explain `forward` as the runtime seam

Artifacts:

- module skeleton
- note on callbacks and boundaries

### 6. Step 4: Separate Finding From Answering

Purpose:

- teach two-phase design
- show why early-answer agents fail

Artifacts:

- navigation signature
- synthesis signature
- diff that removes answer generation from the inner loop

### 7. Step 5: Make State Explicit

Purpose:

- add `TurnState` or similar `T::Struct`
- track budget, evidence, search history, fetched docs

Artifacts:

- state struct
- checkpoint-style update flow

### 8. Step 6: Add Async Fan-Out

Purpose:

- show modern Ruby concurrency in service of the agent
- fetch multiple candidate documents concurrently

Artifacts:

- `Async` / `Async::Barrier` example
- before/after diff

### 9. Step 7: Make The Loop Observable

Purpose:

- add step events, traces, and checkpoint concepts
- connect to the auditability argument

Artifacts:

- `on_step` callback example
- example step payload
- note on UI/operator visibility

### 10. What To Ship

Purpose:

- distill the production checklist

Checklist candidates:

- typed input/output
- typed tools
- bounded loop
- explicit state
- async where it matters
- traces
- tests

### 11. What To Read Next

Purpose:

- keep the single page primary
- use the rest of the site as secondary depth

Candidates:

- API reference links
- blog articles
- examples directory

## Writing Rules

Every main section should answer:

- what it is
- why it matters
- what to do next

Every implementation step should include:

- a small code block
- a small diff block
- one paragraph explaining why the diff matters

Every advanced idea should earn its place by solving a problem introduced earlier in the page.
