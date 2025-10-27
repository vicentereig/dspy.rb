# ADR 014: Prompt vs Context Documentation Restructure

## Status
Accepted - 2025-10-07

## Context
- DSPy.rb documentation has grown large enough that prompt-engineering guidance (signatures, predictors, optimization workflows) is mixed with runtime/context-engineering topics (fiber-local LMs, observability, storage, async execution).
- The existing `core-concepts/modules.md` tried to cover both program structure and runtime behavior, resulting in a 500+ line page that was hard to navigate.
- Two generated inventories capture the current state of the docs:
  - `adr/prompt_tree.txt` – section tree for all prompt-engineering materials with `path:line` anchors.
  - `adr/context_tree.txt` – section tree for context-engineering materials.
- Consolidation candidates and re-org ideas are documented in `adr/context_consolidation_plan.md`.

## Decision
- Split runtime guidance out of `core-concepts/modules.md` into a dedicated `core-concepts/module-runtime-context.md` page that lives between “Modules” and “Event System”.
- Track the prompt vs context doc trees in the ADR folder so future reorganizations can diff against a known baseline.
- Use the context consolidation plan as the working document for merging overlapping async, persistence/registry, observability, and fiber-local content.

## Consequences
- Navigation now differentiates between building modules (prompt engineering) and operating them (context engineering).
- Future documentation work should update the inventories in `adr/prompt_tree.txt` and `adr/context_tree.txt` when large moves happen.
- Follow-up actions include executing the consolidation plan, updating sidebars, and ensuring marketing articles link to canonical docs rather than duplicating implementation details.
