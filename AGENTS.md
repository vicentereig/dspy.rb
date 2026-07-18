# Repository Guidelines

These are the shared instructions for coding agents working in DSPy.rb.
User and system instructions take precedence over this file. `CLAUDE.md`
imports this file for Claude Code and may add Claude-specific notes.

## Source of truth

- Code and tests define observed behavior.
- `Gemfile`, gemspecs, and `Gemfile.lock` define dependency constraints and resolved versions.
- CI workflows define supported quality gates and feature flags.
- ADRs define architectural intent; public documentation in `docs/src/` must stay synchronized with behavior.
- `CONTRIBUTING.md` is the human onboarding guide; keep its commands aligned with this file and CI.

## Environment and dependencies

- Use the Ruby version in `.ruby-version` (currently 3.4.5) for local development and CI.
- `.tool-versions` is an asdf compatibility declaration; it does not override `.ruby-version` for rbenv or CI.
- Install dependencies with `rbenv exec bundle install`.
- Optional providers and sibling gems are enabled through the `DSPY_WITH_*` flags documented in `Gemfile` and CI.
- Copy `.env.sample` to `.env` for local configuration. Never commit `.env`, API keys, provider tokens, or customer data.
- Library code must remain compatible with each affected gemspec's `required_ruby_version`; the development pin is not the compatibility floor.

## Repository layout

- `lib/` — core DSPy.rb and sibling gems (providers, adapters, evals, o11y, GEPA, datasets, and related packages).
- `spec/` — RSpec suites; unit and integration suites may be nested below these directories.
- `spec/vcr_cassettes/` — recorded HTTP interactions.
- `examples/` — runnable demos.
- `docs/src/` — documentation sources; `docs/` contains the site and its tooling.
- `adr/` — architecture decision records.
- `release_notes/` — release notes when present.

## Coding conventions

- Ruby uses two-space indentation and preferably frozen string literals.
- Use snake_case filenames and CamelCase constants.
- Prefer small, composable, testable methods; extract methods for clarity, cohesion, or testability, not only reuse.
- Use Sorbet runtime types and typed critical interfaces where the surrounding code uses them.
- Preserve established domain vocabulary and public API compatibility unless the task explicitly changes it.
- Avoid speculative abstractions, unrelated cleanup, and comments that merely restate code.

## Verification matrix

Choose checks based on the files and behavior changed. Do not run paid provider calls or unrelated full suites by default.

| Change | Minimum verification |
| --- | --- |
| Pure Ruby logic or core module | Focused unit specs, then relevant broader unit specs |
| Provider/adaptor behavior | Focused unit specs; integration/VCR coverage when the provider boundary changes |
| GEPA, optimizers, datasets, or sibling gem | The affected feature-flagged CI slice and focused specs |
| Documentation source | `ruby docs/scripts/check_documentation_quality.rb` from the repository root |
| Release or cross-gem change | Relevant focused suites plus the full CI-equivalent suite when practical and explicitly requested |

Run commands through the pinned environment, for example:

```bash
rbenv exec bundle exec rspec spec/unit/path/to/file_spec.rb
rbenv exec bundle exec rspec spec/integration/path/to/file_spec.rb
ruby docs/scripts/check_documentation_quality.rb
```

Do not advertise `srb tc` or RuboCop as required gates until their dependencies, configuration, and CI jobs exist. If a check is unavailable, report that fact rather than substituting an invented result.

## Tests and provider calls

- Test behavior at the lowest useful level; add integration coverage when behavior crosses an integration boundary.
- Keep pure logic tests separate from tests that contact an LLM or external service.
- Replay existing VCR cassettes by default.
- Live requests and recording or replacing cassettes require explicit maintainer authorization.
- Use synthetic or public inputs only; never record production secrets, customer content, or sensitive prompts/responses.
- Inspect cassette diffs for secrets and personal data before committing. Preserve existing API-key skip guards and sentinel-key conventions.

## Documentation

When behavior or a public API changes, update the relevant `docs/src/` pages, examples, YARD comments, and release notes as appropriate. Do not claim support that code, tests, or CI do not provide. Follow the documentation review workflow in `CONTRIBUTING.md` for meaning-changing public docs.

## Delegating work to subagents

Delegate bounded, independent work; reviewers should be read-only by default. Do not delegate secrets, paid external calls, remote mutations, or concurrent edits to the same files. The parent agent owns integration, final verification, and user communication. Require each delegate to report evidence, changed files, checks run, and uncertainty.

When Codex subagents are available, use capability rather than model branding:

- **Luna, low/medium:** inventory, small documentation edits, focused regression specs, mechanical consistency checks.
- **Terra, medium/high:** routine implementation, debugging, provider adapters, test additions, and toolchain reconciliation.
- **Sol, high/xhigh/max:** architecture, security, cross-gem compatibility, ambiguous debugging, and adversarial review. Use ultra only for exceptional research-like work.

Model names and availability are platform-specific; do not assume Claude uses these names. For a substantial change, prefer an implementation delegate followed by an independent reviewer at equal or greater reasoning effort.

## Git and external state

- Inspect `git status --short` and the diff before editing or staging.
- Preserve unrelated user changes. Stage only task-owned paths; never use a blanket add when the worktree is shared or dirty.
- Commit, push, pull/rebase, create or close issues, modify project boards, clean stashes, prune remotes, publish gems, or otherwise mutate external state only when the user explicitly requests it or the task explicitly authorizes it.
- Never clear stashes or overwrite another contributor's work.
- Before an authorized commit, run the applicable verification matrix and inspect the staged diff for secrets and generated artifacts.
- If delivery is not authorized, leave a clear local handoff: changed files, checks run, remaining risks, and exact next steps.

## Dependency and release changes

For dependency work, inspect the relevant gemspec and `Gemfile` constraints, the resolved entries in `Gemfile.lock`, upstream versioned documentation/changelog, and security advisories. Keep lockfile changes minimal and review them. Publishing to RubyGems is maintainer-only and requires explicit authorization, artifact inspection, a clean intended state, and the project release runbook.
