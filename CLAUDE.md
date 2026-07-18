# Claude Code guidance

@AGENTS.md

The imported `AGENTS.md` is the canonical repository policy shared with
Codex and other coding agents. Keep Claude-specific guidance here only; do
not duplicate versions, commands, testing rules, or Git policy.

## Claude-specific workflow

- Treat repository instructions as context, not as authorization to mutate external state. Ask before commits, pushes, issue/project changes, releases, or paid provider calls unless the user already authorized that action.
- For ambiguous work where a missing choice materially changes behavior, ask one concise question. Otherwise state assumptions and proceed.
- For broad or cross-gem changes, begin with a short plan and identify the affected CI slices before editing.
- Use plan mode for architecture changes, public API changes, release work, and changes spanning multiple sibling gems.
- Keep subagent tasks bounded and non-overlapping. Prefer a read-only adversarial reviewer after implementation; the parent agent integrates changes and runs final checks.

## Repository orientation

Start with the relevant code, tests, `README.md`, `CONTRIBUTING.md`, `docs/README.md`, and ADR index rather than relying on this file's historical inventories. Public documentation sources live under `docs/src/`.

Useful entry points include:

- Core library: `lib/dspy/`
- Providers: `lib/dspy/openai/`, `lib/dspy/anthropic/`, `lib/dspy/gemini/`, and `lib/dspy/ruby_llm/`
- Optimization: `lib/gepa/` and `lib/dspy/teleprompt/`
- Observability: `lib/dspy/observability/` and `dspy-o11y*` gems
- Typed serialization: `lib/sorbet/toon/`
- Tests: `spec/unit/`, `spec/integration/`, and their nested feature directories

When changing a public contract, verify the implementation and its tests first, then update the smallest relevant documentation set. Treat ADRs as architectural intent, not as proof that current behavior still matches them.

## Claude shortcuts

These are prompts, not shell commands or permissions:

- **Plan:** summarize affected files, alternatives, risks, and focused checks before implementation.
- **Review:** inspect the diff skeptically for behavior, compatibility, security, test gaps, and documentation drift.
- **Adversarial review:** assume the change is wrong; search for contradictory instructions, stale commands, unsafe external effects, and missing failure-path coverage.
